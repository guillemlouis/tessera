import Foundation
import SwiftUI
import AppKit

struct DecodedJWT {
    let header: [String: Any]
    let payload: [String: Any]
    let headerJSON: String
    let payloadJSON: String
    let signature: String

    var algorithm: String? { header["alg"] as? String }
    var type: String? { header["typ"] as? String }
    var keyID: String? { header["kid"] as? String }

    /// Reads a NumericDate claim (seconds since epoch), e.g. exp, iat, nbf.
    func date(_ claim: String) -> Date? {
        guard let number = payload[claim] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue)
    }
}

enum JWTError: LocalizedError {
    case encrypted
    case segmentCount(Int)
    case invalidBase64(String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .encrypted:
            return "This looks like an encrypted token (JWE, 5 segments). It cannot be read without the key."
        case .segmentCount(let count):
            return "A JWT has 3 segments separated by dots. Found \(count)."
        case .invalidBase64(let part):
            return "The \(part) segment is not valid Base64URL."
        case .invalidJSON(let part):
            return "The \(part) segment does not contain a JSON object."
        }
    }
}

enum JWTDecoder {
    static func decode(_ raw: String) throws -> DecodedJWT {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }

        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 5 { throw JWTError.encrypted }
        guard parts.count == 3 else { throw JWTError.segmentCount(parts.count) }

        let (header, headerJSON) = try object(from: parts[0], part: "header")
        let (payload, payloadJSON) = try object(from: parts[1], part: "payload")

        return DecodedJWT(header: header, payload: payload,
                          headerJSON: headerJSON, payloadJSON: payloadJSON,
                          signature: parts[2])
    }

    private static func object(from segment: String, part: String) throws -> ([String: Any], String) {
        let data = try base64URLDecode(segment, part: part)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw JWTError.invalidJSON(part)
        }
        let pretty = try JSONSerialization.data(
            withJSONObject: dictionary,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return (dictionary, String(decoding: pretty, as: UTF8.self))
    }

    private static func base64URLDecode(_ segment: String, part: String) throws -> Data {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else {
            throw JWTError.invalidBase64(part)
        }
        return data
    }
}

/// JSON syntax colouring in the style of Xcode, using system colours.
enum JSONHighlighter {
    static func highlight(_ json: String, size: CGFloat, lineSpacing: CGFloat) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let paragraph = TextStyle.paragraph(lineSpacing: lineSpacing)
        let regular = TextStyle.mono(size)
        let keyFont = TextStyle.mono(size, .semibold)
        let chars = Array(json)
        var i = 0

        func append(_ text: String, _ color: NSColor, _ font: NSFont) {
            output.append(TextStyle.plain(text, font: font, color: color, paragraph: paragraph))
        }

        func isTokenStart(_ c: Character) -> Bool {
            c == "\"" || c == "-" || c.isNumber || c.isLetter
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == "\"" { break }
                    j += 1
                }
                let end = min(j, chars.count - 1)
                var k = end + 1
                while k < chars.count, chars[k] == " " { k += 1 }
                let isKey = k < chars.count && chars[k] == ":"
                if isKey {
                    append(String(chars[i...end]), .labelColor, keyFont)
                } else {
                    append(String(chars[i...end]), .systemRed, regular)
                }
                i = end + 1
            } else if c == "-" || c.isNumber {
                var j = i
                while j < chars.count, "-+.eE0123456789".contains(chars[j]) { j += 1 }
                append(String(chars[i..<j]), .systemBlue, regular)
                i = j
            } else if c.isLetter {
                var j = i
                while j < chars.count, chars[j].isLetter { j += 1 }
                append(String(chars[i..<j]), .systemPink, regular)
                i = j
            } else {
                var j = i
                while j < chars.count, !isTokenStart(chars[j]) { j += 1 }
                append(String(chars[i..<j]), .tertiaryLabelColor, regular)
                i = j
            }
        }
        return output
    }
}

enum TokenStatus {
    case valid, expired, notYetValid

    init(now: Date, notBefore: Date?, expires: Date?) {
        if let expires, now >= expires {
            self = .expired
        } else if let notBefore, now < notBefore {
            self = .notYetValid
        } else {
            self = .valid
        }
    }

    var label: String {
        switch self {
        case .valid: return "Valid"
        case .expired: return "Expired"
        case .notYetValid: return "Not Yet Valid"
        }
    }

    var symbol: String {
        switch self {
        case .valid: return "checkmark.seal.fill"
        case .expired: return "xmark.seal.fill"
        case .notYetValid: return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .valid: return .green
        case .expired: return .red
        case .notYetValid: return .orange
        }
    }
}

enum Durations {
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func string(_ interval: TimeInterval) -> String {
        formatter.string(from: abs(interval)) ?? ""
    }
}
