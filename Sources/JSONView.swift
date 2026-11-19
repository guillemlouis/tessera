import SwiftUI

struct JSONView: View {
    @AppStorage("json.indent") private var indent: JSONIndent = .two
    @State private var input = ""
    @State private var status: Status?
    @Environment(\.contentOpacity) private var contentOpacity

    private enum Status {
        case success(String)
        case failure(String)
    }

    private var inputIsEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSection("JSON") {
                HStack(spacing: 6) {
                    IconButton(systemName: "doc.on.clipboard", help: "Paste") {
                        if let clip = Clipboard.read() {
                            input = clip
                            setStatus(nil)
                        }
                    }
                    IconButton(systemName: "xmark.circle", help: "Clear") {
                        input = ""
                        setStatus(nil)
                    }
                    .disabled(input.isEmpty && status == nil)
                }
            } content: {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $input)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(height: 110)
                        if input.isEmpty {
                            EditorPlaceholder(text: "Paste JSON here, or leave empty to use the clipboard")
                        }
                    }
                    .insetWell()

                    HStack(spacing: 8) {
                        Text("Indent")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        SegmentedPicker(selection: $indent, compact: true)
                        Spacer(minLength: 8)
                        Button("Minify") { run(minify: true) }
                            .secondaryActionStyle()
                            .controlSize(.regular)
                            .keyboardShortcut("m", modifiers: [.command, .shift])
                            .help("Minify and copy (Shift+Command+M)")
                        Button {
                            run(minify: false)
                        } label: {
                            Text(inputIsEmpty ? "Format Clipboard" : "Format")
                        }
                        .primaryActionStyle()
                        .controlSize(.regular)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Format and copy (Command+Return)")
                    }
                    .controlSize(.small)
                }
            }

            if let current = status {
                statusLabel(current)
                    .padding(.horizontal, 4)
                    .opacity(contentOpacity)
                    .transition(.opacity.animation(Motion.swiftUI.delay(0.08)))
            }
        }
    }

    private func statusLabel(_ status: Status) -> some View {
        let isSuccess: Bool
        let text: String
        switch status {
        case .success(let message): isSuccess = true; text = message
        case .failure(let message): isSuccess = false; text = message
        }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? Color.green : Color.orange)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
    }

    private func setStatus(_ newStatus: Status?) {
        withAnimation(Motion.swiftUI) { status = newStatus }
    }

    /// Formats or minifies the input (or the clipboard when the input is empty)
    /// and puts the result on the clipboard. The result is not displayed.
    private func run(minify: Bool) {
        let fromClipboard = inputIsEmpty
        let source = fromClipboard ? (Clipboard.read() ?? "") : input

        do {
            let result = minify
                ? try JSONFormatter.minify(source)
                : try JSONFormatter.format(source, indent: indent)
            Clipboard.copy(result)

            let lines = result.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
            let size = ByteCountFormatter.string(fromByteCount: Int64(result.utf8.count), countStyle: .file)
            let action = minify ? "Minified" : "Formatted"
            let origin = fromClipboard ? " clipboard" : ""
            setStatus(.success("\(action)\(origin): \(lines.formatted()) lines, \(size). Copied."))
        } catch {
            setStatus(.failure(error.localizedDescription))
        }
    }
}
