import SwiftUI
import AppKit

// MARK: - Panel geometry (concentric radii, as in macOS 26)

/// The window is larger than the visible panel by `insets`, which leaves transparent room for the shadow.
enum PanelLayout {
    static let panelWidth: CGFloat = 400
    static let tileRadius: CGFloat = 26
    static let tilePadding: CGFloat = 14
    /// Space between the pills, the tiles and the Settings capsule (also used inside tools).
    static let spacing: CGFloat = 14
    static let insets = EdgeInsets(top: 6, leading: 24, bottom: 36, trailing: 24)

    static var windowWidth: CGFloat { panelWidth + insets.leading + insets.trailing }
    /// Width available inside a tile.
    static var sectionContentWidth: CGFloat { panelWidth - 2 * tilePadding }
}

// MARK: - Liquid Glass
// Real Liquid Glass needs the macOS 26 SDK (Swift 6.2) at build time and macOS 26 at run time.
// Otherwise EmulatedGlass draws a close approximation: translucent material, a soft top sheen
// and a light specular rim.

struct EmulatedGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let material: Material
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        return content
            .background {
                ZStack {
                    shape.fill(material)
                    if let tint {
                        shape.fill(tint.opacity(0.9))
                    }
                    shape.fill(
                        LinearGradient(colors: [Color.white.opacity(dark ? 0.07 : 0.22), .clear],
                                       startPoint: .top, endPoint: .center)
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(dark ? 0.32 : 0.75),
                                            Color.white.opacity(dark ? 0.04 : 0.10),
                                            Color.white.opacity(dark ? 0.14 : 0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.75
                )
            }
    }
}

#if compiler(>=6.2)
extension View {
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil,
                                         material: Material = .ultraThinMaterial,
                                         interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            } else {
                self.glassEffect(.regular.interactive(interactive), in: shape)
            }
        } else {
            self.modifier(EmulatedGlass(shape: shape, tint: tint, material: material))
        }
    }

    /// Groups glass shapes so they sample and blend together, as in Control Center.
    @ViewBuilder
    func glassGroup(spacing: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

}
#else
extension View {
    func liquidGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil,
                                         material: Material = .ultraThinMaterial,
                                         interactive: Bool = false) -> some View {
        self.modifier(EmulatedGlass(shape: shape, tint: tint, material: material))
    }

    func glassGroup(spacing: CGFloat) -> some View {
        self
    }

}
#endif

extension View {
    func toastBackground() -> some View {
        self.frame(height: 30)
            .clipShape(Capsule())
            .background(GlassBackground(cornerRadius: 15))
            .overlay(GlassRim(shape: Capsule()))
    }
}

// MARK: - Native glass backdrop
// AppKit glass samples the desktop behind the window, which SwiftUI's glass cannot do
// in a borderless floating panel (it renders dark). macOS 26: NSGlassEffectView.
// Earlier macOS or SDK: behind-window blur, as used by Control Center and menus.

/// How much the glass blurs what is behind it. Chosen in the ... menu.
enum GlassStyle: String, CaseIterable, Identifiable {
    case clear, balanced, frosted

    static let storageKey = "toolbox.glassStyle"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .balanced: return "Balanced"
        case .frosted: return "Frosted"
        }
    }
}

/// Opacity applied to the AppKit glass. SwiftUI's .opacity does not reach AppKit views,
/// so transitions pass it explicitly through the environment.
private struct GlassOpacityKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

/// Opacity and horizontal offset of the content drawn on top of the glass (text, controls),
/// used to reveal a tool's content while its glass stays put.
private struct ContentOpacityKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

private struct ContentOffsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var glassOpacity: Double {
        get { self[GlassOpacityKey.self] }
        set { self[GlassOpacityKey.self] = newValue }
    }

    var contentOpacity: Double {
        get { self[ContentOpacityKey.self] }
        set { self[ContentOpacityKey.self] = newValue }
    }

    var contentOffset: CGFloat {
        get { self[ContentOffsetKey.self] }
        set { self[ContentOffsetKey.self] = newValue }
    }
}

/// Glass behind a tile, in the style picked in the ... menu.
/// Recreated when the style changes, because each style may use a different AppKit view.
struct GlassBackground: View {
    var cornerRadius: CGFloat
    @AppStorage(GlassStyle.storageKey) private var style: GlassStyle = .balanced
    @Environment(\.glassOpacity) private var opacity

    var body: some View {
        GlassBackdrop(cornerRadius: cornerRadius, style: style, opacity: opacity)
            .id(style)
    }
}

struct GlassBackdrop: NSViewRepresentable {
    var cornerRadius: CGFloat
    var style: GlassStyle
    var opacity: Double = 1

    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), style != .frosted {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            switch style {
            case .clear:
                // Clear variant (style 1), set only if this macOS exposes the property.
                if glass.responds(to: NSSelectorFromString("setStyle:")) {
                    glass.setValue(NSNumber(value: 1), forKey: "style")
                }
            case .balanced:
                // Regular, frosted glass, lifted with a light white tint so it stays bright.
                if glass.responds(to: NSSelectorFromString("setTintColor:")) {
                    glass.setValue(NSColor.white.withAlphaComponent(0.12), forKey: "tintColor")
                }
            case .frosted:
                break
            }
            return glass
        }
        #endif
        // Frosted, or macOS before 26: behind-window blur as used by menus and Control Center.
        let view = NSVisualEffectView()
        view.material = style == .frosted ? .hudWindow : .menu
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        // Behind-window blur ignores layer clipping; a resizable mask image rounds it.
        view.maskImage = Self.roundedMask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.alphaValue = CGFloat(opacity)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Bright refracting edge, as on Control Center modules.
struct GlassRim<S: InsettableShape>: View {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            // Outer specular edge: bright at the top left and bottom right, faint on the sides.
            shape.strokeBorder(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(dark ? 0.55 : 0.85),
                        Color.white.opacity(0.08),
                        Color.white.opacity(dark ? 0.40 : 0.70),
                        Color.white.opacity(0.08),
                        Color.white.opacity(dark ? 0.55 : 0.85)
                    ]),
                    center: .center,
                    angle: .degrees(225)
                ),
                lineWidth: 1.2
            )
            // Soft inner glow just inside the edge.
            shape.inset(by: 1.2)
                .strokeBorder(Color.white.opacity(dark ? 0.10 : 0.25), lineWidth: 2)
                .blur(radius: 2)
        }
        .allowsHitTesting(false)
    }
}

/// Animates a frame height frame by frame, so the AppKit glass behind a tile
/// resizes smoothly together with the SwiftUI content.
struct AnimatedHeight: AnimatableModifier {
    var height: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(height: height > 0 ? height : nil, alignment: .top)
    }
}

private struct TileHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Capsule buttons (Control Center style)
// Main action: white capsule with accent-coloured text, like an active Control Center toggle.
// Secondary action: translucent white capsule.

struct CapsuleGlassButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        CapsuleGlassButton(configuration: configuration, prominent: prominent)
    }

    private struct CapsuleGlassButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize

        var body: some View {
            let small = controlSize == .small || controlSize == .mini
            configuration.label
                .font(.system(size: small ? 12 : 13, weight: .semibold))
                .foregroundStyle(prominent ? Color.accentColor : Color.primary)
                .padding(.horizontal, small ? 12 : 18)
                .padding(.vertical, small ? 5 : 8)
                .background(
                    Capsule().fill(prominent ? Color.white : Color.white.opacity(0.14))
                )
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(prominent ? 0 : 0.22), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(prominent ? 0.20 : 0), radius: 5, x: 0, y: 2)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

extension View {
    func primaryActionStyle() -> some View {
        self.buttonStyle(CapsuleGlassButtonStyle(prominent: true))
    }

    func secondaryActionStyle() -> some View {
        self.buttonStyle(CapsuleGlassButtonStyle(prominent: false))
    }
}

// MARK: - Glass tile (Control Center module)

struct PanelSection<Accessory: View, Content: View>: View {
    private let title: String?
    private let accessory: Accessory
    private let content: Content
    @Environment(\.contentOpacity) private var contentOpacity
    @Environment(\.contentOffset) private var contentOffset

    init(_ title: String? = nil,
         @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    @State private var displayedHeight: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PanelLayout.tileRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    Spacer(minLength: 8)
                    accessory
                }
                .frame(minHeight: 24)
            }
            content
        }
        .opacity(contentOpacity)                                // fades the content, not the glass
        .offset(x: contentOffset)                               // slides inside the tile (clipped)
        .padding(PanelLayout.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)          // natural height, never squeezed
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TileHeightKey.self, value: proxy.size.height)
            }
        )
        .modifier(AnimatedHeight(height: displayedHeight))      // visible height, animated
        .clipShape(shape)                                       // reveal, never overflow
        .background(GlassBackground(cornerRadius: PanelLayout.tileRadius))
        .overlay(GlassRim(shape: shape))
        .onPreferenceChange(TileHeightKey.self) { height in
            guard height > 0 else { return }
            if displayedHeight == 0 {
                displayedHeight = height
            } else if abs(height - displayedHeight) > 0.5 {
                withAnimation(Motion.swiftUI) { displayedHeight = height }
            }
        }
    }
}

extension PanelSection where Accessory == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

/// A tile whose content can be shown or hidden by clicking its header (like History).
/// The open/closed state is saved per section. Buttons in the header (accessory) keep
/// working without toggling.
struct CollapsibleSection<Accessory: View, Content: View>: View {
    private let title: String
    private let storageKey: String
    private let accessory: Accessory
    private let content: Content

    // Plain @State so the toggle animates; saved to UserDefaults separately.
    @State private var expanded: Bool

    init(_ title: String,
         storageKey: String,
         defaultExpanded: Bool = true,
         @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.storageKey = storageKey
        self.accessory = accessory()
        self.content = content()
        _expanded = State(initialValue:
            UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultExpanded)
    }

    var body: some View {
        PanelSection {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    Spacer(minLength: 8)
                    accessory
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 14)
                }
                .frame(minHeight: 24)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
                .help(expanded ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")

                if expanded {
                    VStack(alignment: .leading, spacing: 10) {
                        content
                    }
                    .padding(.top, 10)
                    // The list stays in place and the growing tile reveals it from the top,
                    // fading in slightly after the tile starts moving.
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(Motion.swiftUI.delay(0.08)),
                            removal: .opacity.animation(.easeOut(duration: 0.2))
                        )
                    )
                }
            }
        }
    }

    private func toggle() {
        withAnimation(Motion.swiftUI) {
            expanded.toggle()
        }
        UserDefaults.standard.set(expanded, forKey: storageKey)
    }
}

extension CollapsibleSection where Accessory == EmptyView {
    init(_ title: String, storageKey: String, defaultExpanded: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.init(title, storageKey: storageKey, defaultExpanded: defaultExpanded,
                  accessory: { EmptyView() }, content: content)
    }
}

/// Slightly darker well for text input inside a tile.
struct InsetWell: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.07))
            )
    }
}

extension View {
    func insetWell() -> some View { modifier(InsetWell()) }
}

// MARK: - Segmented control (macOS 26 style: capsule track, sliding thumb)

protocol SegmentOption: CaseIterable, Identifiable, Hashable {
    var title: String { get }
}

/// Frames of the segments, so a single thumb can be positioned under the selected one.
private struct SegmentFramesKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct SegmentedPicker<Option: SegmentOption>: View {
    @Binding var selection: Option
    /// Stretch across the available width instead of hugging the labels.
    var fill = false
    var compact = false
    /// No track of its own.
    var bare = false

    @Environment(\.colorScheme) private var colorScheme

    private var options: [Option] { Array(Option.allCases) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = option
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: compact ? 11 : 13, weight: .semibold))
                        // Same colour for every option: a text colour cannot animate,
                        // so changing it on selection made the labels blink.
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, compact ? 10 : 14)
                        .padding(.vertical, compact ? 4 : 7)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .anchorPreference(key: SegmentFramesKey.self, value: .bounds) { [index: $0] }
            }
        }
        // One permanent thumb that slides to the selected segment. (A thumb drawn per segment
        // is removed and re-inserted on every click, which made it blink.)
        .backgroundPreferenceValue(SegmentFramesKey.self) { frames in
            GeometryReader { proxy in
                if let index = options.firstIndex(of: selection), let anchor = frames[index] {
                    let rect = proxy[anchor]
                    // Translucent white in Dark mode (white labels stay readable),
                    // solid white in Light mode (black labels).
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.26) : Color.white)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.25 : 0), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 1)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .padding(bare ? 0 : 2)
        .background {
            if !bare {
                Capsule().fill(Color.primary.opacity(0.10))
            }
        }
        .fixedSize(horizontal: !fill, vertical: true)
    }
}

// MARK: - Small elements

/// Round button with an SF Symbol, for tile headers (Paste, Clear, Copy).
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
    }
}

/// Button style with no visual feedback on press (the plain style dims the label).
struct NoPressEffectButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
    }
}

/// Small capsule label, e.g. the JWT algorithm.
struct Tag: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .fixedSize()
    }
}

/// Capsule progress bar (used for the JWT lifetime).
struct CapsuleProgress: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(geometry.size.width * min(max(value, 0), 1), 6))
            }
        }
        .frame(height: 6)
    }
}

/// Placeholder shown on top of an empty TextEditor.
struct EditorPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.leading, 5)
            .allowsHitTesting(false)
    }
}

// MARK: - Clipboard

enum Clipboard {
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        CopyFeedback.shared.flash()
    }

    static func read() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
