import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct ToolboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The UI lives in a custom panel under the status item; this scene only satisfies the App protocol.
        Settings { EmptyView() }
    }
}

extension Notification.Name {
    /// Posted after the panel has closed and faded out.
    static let toolboxPanelDidHide = Notification.Name("ToolboxPanelDidHide")
}

/// One timing curve shared by SwiftUI and AppKit so the panel and its content move together.
enum Motion {
    static let duration: Double = 0.5
    private static let curve: (Float, Float, Float, Float) = (0.32, 0.72, 0.0, 1.0)

    static var swiftUI: Animation {
        .timingCurve(Double(curve.0), Double(curve.1), Double(curve.2), Double(curve.3), duration: duration)
    }

    static var appKit: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: curve.0, curve.1, curve.2, curve.3)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let autosaveName = "ToolboxStatusItem"
    /// Space between the menu bar and the pills, matching Control Center.
    private static let gapBelowMenuBar: CGFloat = 12

    private var statusItem: NSStatusItem?
    private let guidStore = GUIDStore()
    private var hotKey: GlobalHotKey?
    private var outsideClickMonitor: Any?

    private lazy var panel = ToolboxPanel(width: PanelLayout.windowWidth)
    /// Fallback height before the panel is first positioned on a screen.
    private var panelHeight: CGFloat = 800
    private var isShowing = false
    private var lastHidden = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        setUpPanel()

        // Option+Command+G opens the panel from anywhere.
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_G),
                              modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.togglePanel()
        }
    }

    /// Switching to another app (Cmd+Tab, Dock) also closes the panel.
    func applicationDidResignActive(_ notification: Notification) {
        hidePanel()
    }

    // MARK: Setup

    private func setUpStatusItem() {
        // New status items are inserted on the left of the others, which on notched Macs
        // can mean behind the notch. Seed a preferred position close to the right edge.
        let positionKey = "NSStatusItem Preferred Position \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(250.0, forKey: positionKey)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.isVisible = true
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "square.grid.2x2.fill",
                                   accessibilityDescription: "Tessera") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "TB"
            }
            button.toolTip = "Tessera (Option+Command+G)"
            button.target = self
            button.action = #selector(togglePanel)
        }
        statusItem = item
    }

    private func setUpPanel() {
        // The window is never resized while open (see targetFrame), so the content
        // height is not needed here.
        let root = RootView()
            .environmentObject(guidStore)

        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []          // the window size is set by targetFrame, not by SwiftUI
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.onDismiss = { [weak self] in self?.hidePanel() }

        // Lay out once off-screen so the first opening already has the right height.
        panel.setFrame(NSRect(x: 0, y: 0, width: PanelLayout.windowWidth, height: panelHeight), display: false)
        hosting.layoutSubtreeIfNeeded()
    }

    // MARK: Show / hide

    @objc private func togglePanel() {
        if isShowing {
            hidePanel()
        } else if Date().timeIntervalSince(lastHidden) > 0.25 {
            // The guard avoids reopening right after a click on the icon closed the panel.
            showPanel()
        }
    }

    private func showPanel() {
        let target = targetFrame()
        panel.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isShowing = true
        statusItem?.button?.highlight(true)
        startOutsideClickMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = Motion.appKit
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    private func hidePanel() {
        guard isShowing else { return }
        isShowing = false
        lastHidden = Date()
        statusItem?.button?.highlight(false)
        stopOutsideClickMonitor()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isShowing else { return }
            self.panel.orderOut(nil)
            // Leaving the app empties the generator display and goes back to the GUID tab
            // (after the fade, so it is not seen).
            self.guidStore.clearCurrent()
            NotificationCenter.default.post(name: .toolboxPanelDidHide, object: nil)
        })
    }

    // MARK: Window frame

    /// The window is transparent and reaches from just under the menu bar to the bottom
    /// of the screen. It is never resized while open: resizing it on every animation frame
    /// made the content twitch. The visible tiles are drawn inside it by SwiftUI, and clicks
    /// on its transparent part go through to whatever is underneath (and close the panel).
    private func targetFrame() -> NSRect {
        let insets = PanelLayout.insets
        let width = PanelLayout.panelWidth
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        var panelX: CGFloat
        if let button = statusItem?.button, isOnScreen(button), let buttonWindow = button.window {
            let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            panelX = buttonFrame.midX - width / 2
        } else {
            // Icon hidden (e.g. behind the notch): open at the top right.
            panelX = visible.maxX - width - 12
        }
        panelX = min(max(panelX, visible.minX + 8), visible.maxX - width - 8)

        let windowTop = visible.maxY - Self.gapBelowMenuBar + insets.top
        let height = windowTop - visible.minY
        panelHeight = height
        return NSRect(x: panelX - insets.leading,
                      y: visible.minY,
                      width: PanelLayout.windowWidth,
                      height: height)
    }

    /// True when the status item is actually visible: on a screen and not behind the notch.
    private func isOnScreen(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window, let screen = window.screen else { return false }
        let frame = window.frame
        let screenFrame = screen.frame

        guard frame.minX >= screenFrame.minX, frame.maxX <= screenFrame.maxX else { return false }

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let notchMinX = screenFrame.minX + left.maxX
            let notchMaxX = screenFrame.minX + right.minX
            if frame.maxX > notchMinX && frame.minX < notchMaxX { return false }
        }
        return true
    }

    // MARK: Outside clicks

    /// Closes the panel on any click in another app, on the desktop or in the menu bar.
    /// (Global mouse monitors do not need Accessibility permission.)
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }
}

/// Borderless, rounded panel that can take keyboard focus (needed for the JWT field).
final class ToolboxPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init(width: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 360),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // the shadow is drawn by SwiftUI (see RootView)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape closes the panel.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

/// System-wide hotkey via Carbon. Does not require Accessibility permission.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &eventType, context, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x54424F58), id: 1) // "TBOX"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
