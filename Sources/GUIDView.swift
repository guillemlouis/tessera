import SwiftUI
import AppKit

struct GUIDView: View {
    @EnvironmentObject private var store: GUIDStore


    private let currentFont = TextStyle.mono(15, .medium)
    private let historyFont = TextStyle.mono(12)
    private let historyMetaFont = NSFont.systemFont(ofSize: 11)
    private let historyLineSpacing: CGFloat = 9
    private let historyVisibleLines = 8

    var body: some View {
        VStack(spacing: PanelLayout.spacing) {
            generator
            history
        }
    }

    // MARK: Generator

    private var generator: some View {
        PanelSection("Generator") {
            IconButton(systemName: "xmark.circle", help: "Clear (history is kept)") {
                withAnimation(.easeOut(duration: 0.2)) { store.clearCurrent() }
            }
            .disabled(store.current == nil)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                // Read-only field (same well as the other tools' inputs): not editable,
                // but selecting or clicking copies, like everywhere else.
                HStack(spacing: 8) {
                    Group {
                        if let current = store.current {
                            SelectableText(
                                attributedText: TextStyle.plain(
                                    current, font: currentFont, color: .labelColor,
                                    paragraph: TextStyle.paragraph(lineBreak: .byClipping)),
                                copyLineOnClick: true
                            )
                            .frame(height: TextStyle.lineHeight(currentFont))
                        } else {
                            // Same style as the placeholders of the other tools' fields.
                            Text("Press Return to generate")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 24)
                .padding(.horizontal, 4)
                .insetWell()

                HStack(spacing: 8) {
                    SegmentedPicker(selection: $store.format, compact: true)
                        .help("D: hyphens   N: digits only   B: braces   P: parentheses")
                    SegmentedPicker(selection: $store.letterCase, compact: true)
                    Spacer(minLength: 8)
                    Button {
                        store.generate()
                    } label: {
                        Text("Generate")
                            .padding(.horizontal, 4)
                    }
                    .primaryActionStyle()
                    .controlSize(.regular)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: History (collapsible tile, closed by default)

    private var history: some View {
        CollapsibleSection("History", storageKey: "guid.historyExpanded", defaultExpanded: false) {
            Text("\(store.history.count)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: store.history.count)
        } content: {
            historyContent
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.history.isEmpty {
                Text("No GUIDs yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    SelectableText(
                        attributedText: historyText(),
                        copyLineOnClick: true,
                        scrollable: store.history.count > historyVisibleLines,
                        transform: GUIDExtractor.extract,
                        onCopy: { store.markCurrent($0) }
                    )
                    .frame(height: historyHeight)
                }
            }

            Divider()

            HStack {
                Picker("Auto-Clear", selection: $store.autoClear) {
                    ForEach(AutoClear.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Spacer()

                Button("Clear History", role: .destructive) {
                    withAnimation(Motion.swiftUI) { store.clearHistory() }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .disabled(store.history.isEmpty)
            }
            .controlSize(.small)
            .font(.system(size: 12))
        }
    }

    private var historyHeight: CGFloat {
        let lines = CGFloat(min(store.history.count, historyVisibleLines))
        return lines * TextStyle.lineHeight(historyFont) + max(lines - 1, 0) * historyLineSpacing + 2
    }

    /// One GUID per line with its age right-aligned.
    /// Selecting several lines copies only the GUIDs (see GUIDExtractor).
    private func historyText() -> NSAttributedString {
        let paragraph = TextStyle.paragraph(
            lineSpacing: historyLineSpacing,
            lineBreak: .byClipping,
            tabStops: [NSTextTab(textAlignment: .right, location: PanelLayout.sectionContentWidth - 2)]
        )
        let output = NSMutableAttributedString()

        for (index, entry) in store.history.enumerated() {
            if index > 0 {
                output.append(TextStyle.plain("\n", font: historyFont, paragraph: paragraph))
            }
            output.append(TextStyle.plain(
                entry.value, font: historyFont,
                color: entry.value == store.current ? .labelColor : .secondaryLabelColor,
                paragraph: paragraph))

            let age = entry.createdAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            output.append(TextStyle.plain(
                "\t" + age, font: historyMetaFont, color: .tertiaryLabelColor, paragraph: paragraph))
        }
        return output
    }
}
