import Foundation
import AppKit

/// An encoded URL (for example from Datadog) split into readable parts.
struct ReadableURL {
    struct PathRow {
        let name: String
        let id: String?
    }

    struct QueryItem {
        let name: String
        let value: String
    }

    let origin: String          // "https://host:port", or empty
    let path: String            // decoded path
    let pathRows: [PathRow]
    let query: [QueryItem]
    let fragment: String?

    /// The whole URL decoded into plain text (not a valid URL any more, but readable).
    var readable: String {
        var text = origin + path
        if !query.isEmpty {
            text += "?" + query.map { $0.value.isEmpty ? $0.name : "\($0.name)=\($0.value)" }
                .joined(separator: "&")
        }
        if let fragment { text += "#" + fragment }
        return text
    }

    init(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        var fragment: String?
        if let hash = text.firstIndex(of: "#") {
            fragment = Self.decode(String(text[text.index(after: hash)...]), plusAsSpace: false)
            text = String(text[..<hash])
        }

        var queryString = ""
        if let mark = text.firstIndex(of: "?") {
            queryString = String(text[text.index(after: mark)...])
            text = String(text[..<mark])
        }

        var origin = ""
        var path = text
        if let scheme = text.range(of: "://") {
            let rest = text[scheme.upperBound...]
            if let slash = rest.firstIndex(of: "/") {
                origin = String(text[..<slash])
                path = String(text[slash...])
            } else {
                origin = text
                path = ""
            }
        } else if queryString.isEmpty, text.contains("="), !text.hasPrefix("/") {
            // Only a query string was pasted, e.g. "$filter=...&$skip=0".
            queryString = text
            path = ""
        }

        let decodedPath = Self.decode(path, plusAsSpace: false)

        self.origin = origin
        self.path = decodedPath
        self.pathRows = Self.pathRows(decodedPath)
        self.query = queryString
            .split(separator: "&", omittingEmptySubsequences: true)
            .map { pair in
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = Self.decode(String(parts[0]), plusAsSpace: true)
                let value = parts.count > 1 ? Self.decode(String(parts[1]), plusAsSpace: true) : ""
                return QueryItem(name: name, value: value)
            }
        self.fragment = fragment
    }

    /// Percent-decodes, treating "+" as a space in query strings. Decodes up to three times,
    /// because some tools (Datadog included) can encode a URL twice.
    static func decode(_ text: String, plusAsSpace: Bool) -> String {
        var current = plusAsSpace ? text.replacingOccurrences(of: "+", with: " ") : text
        for _ in 0..<3 {
            guard current.contains("%"),
                  let next = current.removingPercentEncoding,
                  next != current else { break }
            current = next
        }
        return current
    }

    private static let guidPattern = try! NSRegularExpression(
        pattern: "^[{(]?[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}[})]?$"
    )

    static func isIdentifier(_ segment: String) -> Bool {
        if !segment.isEmpty, segment.allSatisfy(\.isNumber) { return true }
        let range = NSRange(location: 0, length: (segment as NSString).length)
        return guidPattern.firstMatch(in: segment, range: range) != nil
    }

    /// Pairs each collection with the identifier that follows it: tenants -> <guid>.
    private static func pathRows(_ path: String) -> [PathRow] {
        let segments = path.split(separator: "/").map(String.init)
        var rows: [PathRow] = []
        var index = 0
        while index < segments.count {
            let segment = segments[index]
            if index + 1 < segments.count, !isIdentifier(segment), isIdentifier(segments[index + 1]) {
                rows.append(PathRow(name: segment, id: segments[index + 1]))
                index += 2
            } else if isIdentifier(segment) {
                rows.append(PathRow(name: "", id: segment))
                index += 1
            } else {
                rows.append(PathRow(name: segment, id: nil))
                index += 1
            }
        }
        return rows
    }
}

/// Breaks long OData expressions onto lines: before every "or" / "and", indented by
/// parenthesis depth, and after top-level commas in long lists ($orderby, $select).
/// Quoted strings ('...', with '' as an escaped quote) are never touched.
enum ODataFormatter {
    static func format(_ text: String) -> String {
        let chars = Array(text)
        let breakCommas = text.count > 40
        var output = ""
        var depth = 0
        var inQuote = false
        var index = 0

        func matches(_ word: String, at position: Int) -> Bool {
            let wordChars = Array(word)
            guard position + wordChars.count <= chars.count else { return false }
            return Array(chars[position..<position + wordChars.count]) == wordChars
        }

        scan: while index < chars.count {
            let c = chars[index]

            if c == "'" {
                if inQuote, index + 1 < chars.count, chars[index + 1] == "'" {
                    output += "''"
                    index += 2
                    continue
                }
                inQuote.toggle()
                output.append(c)
                index += 1
                continue
            }

            if !inQuote {
                if c == "(" { depth += 1 }
                if c == ")" { depth = max(0, depth - 1) }

                for op in [" or ", " and "] where matches(op, at: index) {
                    output += "\n" + String(repeating: "  ", count: depth)
                        + op.trimmingCharacters(in: .whitespaces) + " "
                    index += op.count
                    continue scan
                }

                if c == ",", depth == 0, breakCommas {
                    output += ",\n"
                    index += 1
                    while index < chars.count, chars[index] == " " { index += 1 }
                    continue
                }
            }

            output.append(c)
            index += 1
        }
        return output
    }
}

/// Colours for URL parts and OData expressions, using system colours.
enum URLHighlighter {
    static let font = TextStyle.mono(11)
    static let boldFont = TextStyle.mono(11, .semibold)
    static let lineSpacing: CGFloat = 3

    private static let keywords: Set<String> = [
        "or", "and", "not", "eq", "ne", "gt", "ge", "lt", "le", "has", "in", "asc", "desc",
        "true", "false", "null"
    ]

    private static let guidRegex = try! NSRegularExpression(
        pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    )

    static var paragraph: NSParagraphStyle {
        TextStyle.paragraph(lineSpacing: lineSpacing, lineBreak: .byCharWrapping)
    }

    /// Strings red, functions teal, keywords purple, GUIDs blue, punctuation dimmed.
    static func value(_ text: String) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        let chars = Array(text)
        var index = 0

        func append(_ string: String, _ color: NSColor) {
            output.append(TextStyle.plain(string, font: font, color: color, paragraph: paragraph))
        }

        while index < chars.count {
            let c = chars[index]
            if c == "'" {
                var end = index + 1
                while end < chars.count {
                    if chars[end] == "'" {
                        if end + 1 < chars.count, chars[end + 1] == "'" { end += 2; continue }
                        break
                    }
                    end += 1
                }
                let last = min(end, chars.count - 1)
                append(String(chars[index...last]), .systemRed)
                index = last + 1
            } else if c.isLetter || c == "$" || c == "_" {
                var end = index
                while end < chars.count, chars[end].isLetter || chars[end].isNumber || "$_/.".contains(chars[end]) {
                    end += 1
                }
                let word = String(chars[index..<end])
                let isFunction = end < chars.count && chars[end] == "("
                if isFunction {
                    append(word, .systemTeal)
                } else if keywords.contains(word.lowercased()) {
                    append(word, .systemPurple)
                } else {
                    append(word, .labelColor)
                }
                index = end
            } else if "(),=&?".contains(c) {
                append(String(c), .tertiaryLabelColor)
                index += 1
            } else {
                append(String(c), .labelColor)
                index += 1
            }
        }
        colourGUIDs(in: output)
        return output
    }

    static func readable(_ url: ReadableURL) -> NSAttributedString {
        let output = NSMutableAttributedString()
        output.append(TextStyle.plain(url.origin, font: font, color: .secondaryLabelColor, paragraph: paragraph))
        output.append(TextStyle.plain(url.path, font: font, color: .labelColor, paragraph: paragraph))
        for (index, item) in url.query.enumerated() {
            output.append(TextStyle.plain(index == 0 ? "?" : "&", font: font,
                                          color: .tertiaryLabelColor, paragraph: paragraph))
            output.append(TextStyle.plain(item.name, font: boldFont, color: .systemPink, paragraph: paragraph))
            if !item.value.isEmpty {
                output.append(TextStyle.plain("=", font: font, color: .tertiaryLabelColor, paragraph: paragraph))
                output.append(value(item.value))
            }
        }
        if let fragment = url.fragment {
            output.append(TextStyle.plain("#" + fragment, font: font, color: .secondaryLabelColor, paragraph: paragraph))
        }
        colourGUIDs(in: output)
        return output
    }

    /// One row per collection: name, then its identifier.
    static func path(_ rows: [ReadableURL.PathRow]) -> NSAttributedString {
        let rowParagraph = TextStyle.paragraph(
            lineSpacing: 8, lineBreak: .byClipping,
            tabStops: [NSTextTab(textAlignment: .left, location: 118)]
        )
        let output = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            if index > 0 {
                output.append(TextStyle.plain("\n", font: font, paragraph: rowParagraph))
            }
            output.append(TextStyle.plain(row.name, font: font, color: .secondaryLabelColor, paragraph: rowParagraph))
            if let id = row.id {
                output.append(TextStyle.plain("\t" + id, font: font, color: .systemBlue, paragraph: rowParagraph))
            }
        }
        return output
    }

    /// Each parameter name on its own line, its (formatted) value indented underneath.
    static func query(_ items: [ReadableURL.QueryItem]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 {
                output.append(TextStyle.plain("\n", font: font, paragraph: paragraph))
            }
            output.append(TextStyle.plain(item.name, font: boldFont, color: .systemPink, paragraph: paragraph))
            let formatted = ODataFormatter.format(item.value)
            for line in formatted.split(separator: "\n", omittingEmptySubsequences: false) {
                output.append(TextStyle.plain("\n  ", font: font, paragraph: paragraph))
                output.append(value(String(line)))
            }
        }
        return output
    }

    /// Plain-text version of `query(_:)`, used to estimate its height.
    static func queryPlain(_ items: [ReadableURL.QueryItem]) -> String {
        items.map { item in
            ([item.name] + ODataFormatter.format(item.value)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "  " + $0 }).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private static func colourGUIDs(in text: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: text.length)
        for match in guidRegex.matches(in: text.string, range: range) {
            text.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
        }
    }

    /// Estimated height of wrapped monospaced text in the given width.
    static func height(of text: String, width: CGFloat, lineSpacing: CGFloat = URLHighlighter.lineSpacing) -> CGFloat {
        let charWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        let perLine = max(Int(width / max(charWidth, 1)), 1)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / Double(perLine)))) }
        return CGFloat(lines) * (TextStyle.lineHeight(font) + lineSpacing) + 2
    }
}
