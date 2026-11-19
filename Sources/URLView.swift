import SwiftUI

struct URLView: View {
    @State private var input = ""

    private var decoded: ReadableURL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ReadableURL(trimmed)
    }

    private let width = PanelLayout.sectionContentWidth

    var body: some View {
        VStack(spacing: PanelLayout.spacing) {
            urlInput

            if let url = decoded {
                readable(url)
                if url.pathRows.contains(where: { $0.id != nil }) {
                    path(url)
                }
                if !url.query.isEmpty {
                    query(url)
                }
            }
        }
    }

    // MARK: Input

    private var urlInput: some View {
        PanelSection("URL") {
            HStack(spacing: 6) {
                IconButton(systemName: "doc.on.clipboard", help: "Paste") {
                    if let clip = Clipboard.read() { input = clip }
                }
                IconButton(systemName: "xmark.circle", help: "Clear") { input = "" }
                    .disabled(input.isEmpty)
            }
        } content: {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $input)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    // Two lines once a URL is pasted: the tiles below show it in full.
                    .frame(height: decoded == nil ? 64 : 30)
                if input.isEmpty {
                    EditorPlaceholder(text: "Paste an encoded URL, e.g. from Datadog")
                }
            }
            .insetWell()
        }
    }

    // MARK: Results

    private func readable(_ url: ReadableURL) -> some View {
        // At most about five lines: Path and Query below show everything in detail.
        let lineHeight = TextStyle.lineHeight(URLHighlighter.font) + URLHighlighter.lineSpacing
        let height = min(URLHighlighter.height(of: url.readable, width: width), lineHeight * 5 + 2)
        return CollapsibleSection("Readable", storageKey: "url.readableExpanded", defaultExpanded: false) {
            IconButton(systemName: "doc.on.doc", help: "Copy readable URL") {
                Clipboard.copy(url.readable)
            }
        } content: {
            SelectableText(attributedText: URLHighlighter.readable(url), scrollable: true)
                .frame(height: height)
        }
    }

    private func path(_ url: ReadableURL) -> some View {
        let font = URLHighlighter.font
        let rows = CGFloat(url.pathRows.count)
        let height = rows * TextStyle.lineHeight(font) + max(rows - 1, 0) * 8 + 2
        return CollapsibleSection("Path", storageKey: "url.pathExpanded") {
            // A click on a row copies its identifier; a selection keeps only the GUIDs.
            SelectableText(
                attributedText: URLHighlighter.path(url.pathRows),
                copyLineOnClick: true,
                transform: GUIDExtractor.extract
            )
            .frame(height: height)
        }
    }

    private func query(_ url: ReadableURL) -> some View {
        let plain = URLHighlighter.queryPlain(url.query)
        // Shown in full; the panel scrolls if the screen is too short.
        let height = URLHighlighter.height(of: plain, width: width)
        return CollapsibleSection("Query", storageKey: "url.queryExpanded") {
            IconButton(systemName: "doc.on.doc", help: "Copy formatted query") {
                Clipboard.copy(plain)
            }
        } content: {
            SelectableText(
                attributedText: URLHighlighter.query(url.query),
                copyLineOnClick: true
            )
            .frame(height: height)
        }
    }
}
