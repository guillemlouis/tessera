import SwiftUI
import ServiceManagement

enum Tool: String, CaseIterable, Identifiable, SegmentOption {
    case guid
    case jwt
    case json
    case url

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guid: return "GUID"
        case .jwt: return "JWT"
        case .json: return "JSON"
        case .url: return "URL"
        }
    }

    var symbol: String {
        switch self {
        case .guid: return "number"
        case .jwt: return "key.fill"
        case .json: return "curlybraces"
        case .url: return "link"
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Natural height of each tool's tiles, keyed by tool, so the container can follow
/// the tool that is coming in rather than the one leaving.
private struct ToolHeightKey: PreferenceKey {
    static let defaultValue: [Tool: CGFloat] = [:]
    static func reduce(value: inout [Tool: CGFloat], nextValue: () -> [Tool: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Reveals the incoming tool: its glass is there immediately (so the desktop never shows
/// through and nothing overlaps), while its content fades in and slides a short way from
/// the direction of the pill, inside each tile.
private struct ToolReveal: AnimatableModifier {
    /// 1 = hidden, 0 = fully shown.
    var progress: CGFloat
    /// +1 = content comes from the right, -1 = from the left.
    var direction: CGFloat

    private static let distance: CGFloat = 18

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.contentOpacity, Double(1 - progress))
            .environment(\.contentOffset, progress * direction * Self.distance)
    }
}

private extension AnyTransition {
    /// The outgoing tool is removed at once; only the incoming content animates.
    static func toolSwitch(direction: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: ToolReveal(progress: 1, direction: direction),
                                 identity: ToolReveal(progress: 0, direction: direction)),
            removal: .identity
        )
    }
}

struct RootView: View {
    // Plain @State so switching animates. The panel always opens on the GUID tab:
    // it is reset when the panel closes (see .toolboxPanelDidHide).
    @State private var selectedTool: Tool = .guid
    /// Direction of the current switch: +1 when moving to a tool on the right.
    @State private var slideDirection: CGFloat = 1
    /// Height of the incoming tool, animated so the footer glides to its new place.
    @State private var toolHeight: CGFloat = 0

    /// Reports the natural height of the content so the window can be sized to it.
    private let onHeightChange: (CGFloat) -> Void

    init(onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.onHeightChange = onHeightChange
    }

    var body: some View {
        // No container: like Control Center, every tile is its own glass shape over the desktop.
        VStack(spacing: PanelLayout.spacing) {
            tabBar

            ScrollView(.vertical) {
                ZStack(alignment: .top) {
                    toolView(selectedTool)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: ToolHeightKey.self,
                                                       value: [selectedTool: proxy.size.height])
                            }
                        )
                        .id(selectedTool)
                        .transition(.toolSwitch(direction: slideDirection))
                }
            }
            // Never taller than the screen: if a tool's tiles are taller, they scroll inside
            // the panel while the pills and the Settings capsule stay put.
            .scrollDisabled(toolHeight <= maxToolHeight)
            .scrollIndicators(.automatic)
            .frame(height: toolHeight > 0 ? min(toolHeight, maxToolHeight) : nil, alignment: .top)
            .onPreferenceChange(ToolHeightKey.self) { heights in
                guard let height = heights[selectedTool], height > 0 else { return }
                if toolHeight == 0 {
                    toolHeight = height
                } else if abs(height - toolHeight) > 0.5 {
                    withAnimation(Motion.swiftUI) { toolHeight = height }
                }
            }

            Footer()
        }
        .frame(width: PanelLayout.panelWidth)
        .padding(PanelLayout.insets)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(ContentHeightKey.self) { height in
            guard height > 0 else { return }
            onHeightChange(height)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolboxPanelDidHide)) { _ in
            // Back to the GUID tab for the next opening, without animation (the panel is hidden).
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTool = .guid
            }
        }
    }

    /// Room left for the tool tiles on the current screen, below the menu bar:
    /// minus the window margins, the pills, the Settings capsule and the spacing between them.
    private var maxToolHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let pills: CGFloat = 44
        let footer: CGFloat = 30
        let spacing = PanelLayout.spacing * 2
        let margins = PanelLayout.insets.top + PanelLayout.insets.bottom + 12   // 12: gap under the menu bar
        return max(screenHeight - pills - footer - spacing - margins, 200)
    }

    @ViewBuilder
    private func toolView(_ tool: Tool) -> some View {
        switch tool {
        case .guid: GUIDView()
        case .jwt: JWTView()
        case .json: JSONView()
        case .url: URLView()
        }
    }

    /// Control Center style pills, one per tool.
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tool.allCases) { tool in
                ToolPill(tool: tool, isActive: tool == selectedTool) {
                    select(tool)
                }
            }
        }
    }

    private func select(_ tool: Tool) {
        guard tool != selectedTool,
              let from = Tool.allCases.firstIndex(of: selectedTool),
              let to = Tool.allCases.firstIndex(of: tool) else { return }

        // Set the direction first, so the outgoing tiles pick up the right exit transition,
        // then switch on the next run loop pass with the animation.
        slideDirection = to > from ? 1 : -1
        DispatchQueue.main.async {
            withAnimation(Motion.swiftUI) {
                selectedTool = tool
            }
        }
    }
}

/// A tool pill: always glass. The active tool shows a white circle with a blue icon,
/// like an enabled Control Center toggle; inactive tools show a faint circle.
private struct ToolPill: View {
    static let height: CGFloat = 44

    let tool: Tool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(isActive ? Color.white : Color.white.opacity(0.16))
                    )
                    .shadow(color: .black.opacity(isActive ? 0.15 : 0), radius: 3, x: 0, y: 1)
                Text(tool.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .fixedSize()            // never truncated
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)     // centred in the pill
            .frame(height: Self.height)
            .background(GlassBackground(cornerRadius: Self.height / 2))
            .clipShape(Capsule())
            .overlay(GlassRim(shape: Capsule()))
            .contentShape(Capsule())
        }
        .buttonStyle(NoPressEffectButtonStyle())
        .help(tool.title)
    }
}

/// Bottom row, like Control Center's "Edit Controls": a small Settings capsule,
/// replaced for a moment by "Copied" after every copy.
private struct Footer: View {
    @ObservedObject private var feedback = CopyFeedback.shared

    var body: some View {
        ZStack {
            if feedback.visible {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Copied")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .toastBackground()
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                AppMenu()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: feedback.visible)
    }
}

struct AppMenu: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(GlassStyle.storageKey) private var glassStyle: GlassStyle = .balanced

    /// Date of the running binary, to check which build is installed.
    static let buildLabel: String = {
        guard let path = Bundle.main.executablePath,
              let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return "Build: unknown" }
        return "Build: " + date.formatted(date: .abbreviated, time: .standard)
    }()

    var body: some View {
        Menu {
            Picker("Glass", selection: $glassStyle) {
                ForEach(GlassStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Divider()
            Text(Self.buildLabel)
            Divider()
            Button("Quit Tessera") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Label("Settings", systemImage: "gearshape")
                .font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(GlassBackground(cornerRadius: 15))
        .clipShape(Capsule())
        .overlay(GlassRim(shape: Capsule()))
        .help("Settings")
        .onChange(of: launchAtLogin) { enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}
