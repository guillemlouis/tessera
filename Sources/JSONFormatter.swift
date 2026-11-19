import Foundation

enum JSONIndent: String, CaseIterable, Identifiable, SegmentOption {
    case two, four, tab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .two: return "2"
        case .four: return "4"
        case .tab: return "tab"
        }
    }

    var unit: String {
        switch self {
        case .two: return "  "
        case .four: return "    "
        case .tab: return "\t"
        }
    }
}

enum JSONFormatter {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func format(_ text: String, indent: JSONIndent) throws -> String {
        try validate(text)
        return reformat(text, indentUnit: indent.unit)
    }

    static func minify(_ text: String) throws -> String {
        try validate(text)
        return reformat(text, indentUnit: nil)
    }

    /// Validates with JSONSerialization, which gives line and column in its error message.
    private static func validate(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure(message: "Nothing to format: the input and the clipboard are empty.")
        }
        guard let data = text.data(using: .utf8) else {
            throw Failure(message: "The text is not valid UTF-8.")
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let nsError = error as NSError
            let detail = nsError.userInfo["NSDebugDescription"] as? String ?? nsError.localizedDescription
            throw Failure(message: "Invalid JSON. \(detail)")
        }
    }

    /// Re-indents token by token instead of parsing into dictionaries,
    /// so key order and number formatting are preserved exactly.
    /// Only called on input that has already been validated.
    private static func reformat(_ text: String, indentUnit: String?) -> String {
        let scalars = Array(text.unicodeScalars)
        let unit = Array((indentUnit ?? "").unicodeScalars)
        let pretty = indentUnit != nil

        var out = String.UnicodeScalarView()
        var level = 0
        var inString = false
        var escaped = false
        var i = 0

        func isWhitespace(_ c: Unicode.Scalar) -> Bool {
            c == " " || c == "\t" || c == "\n" || c == "\r"
        }

        func newline() {
            out.append("\n")
            for _ in 0..<max(level, 0) { out.append(contentsOf: unit) }
        }

        while i < scalars.count {
            let c = scalars[i]

            if inString {
                out.append(c)
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                i += 1
                continue
            }

            switch c {
            case " ", "\t", "\n", "\r":
                break
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                out.append(c)
                // Keep empty containers compact: {} and []
                let close: Unicode.Scalar = c == "{" ? "}" : "]"
                var j = i + 1
                while j < scalars.count, isWhitespace(scalars[j]) { j += 1 }
                if j < scalars.count, scalars[j] == close {
                    out.append(close)
                    i = j
                } else {
                    level += 1
                    if pretty { newline() }
                }
            case "}", "]":
                level -= 1
                if pretty { newline() }
                out.append(c)
            case ",":
                out.append(c)
                if pretty { newline() }
            case ":":
                out.append(c)
                if pretty { out.append(" ") }
            default:
                out.append(c)
            }
            i += 1
        }
        return String(out)
    }
}
