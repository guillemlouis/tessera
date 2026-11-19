import SwiftUI
import AppKit

enum JWTSection: String, CaseIterable, Identifiable, SegmentOption {
    case header, payload, signature

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct JWTView: View {
    // Tokens are kept in memory only and never written to disk.
    @State private var input = ""
    @State private var section: JWTSection = .payload

    private var decoded: Result<DecodedJWT, Error>? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Result { try JWTDecoder.decode(trimmed) }
    }

    var body: some View {
        VStack(spacing: PanelLayout.spacing) {
            tokenInput

            if let result = decoded {
                switch result {
                case .success(let jwt):
                    validity(jwt)
                    decodedSection(jwt)
                case .failure(let error):
                    PanelSection {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error.localizedDescription)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Input

    private var tokenInput: some View {
        PanelSection("Token") {
            HStack(spacing: 6) {
                IconButton(systemName: "doc.on.clipboard", help: "Paste (Shift+Command+V)") {
                    if let clip = Clipboard.read() { input = clip }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                IconButton(systemName: "xmark.circle", help: "Clear") { input = "" }
                    .disabled(input.isEmpty)
            }
        } content: {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $input)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 64)
                if input.isEmpty {
                    EditorPlaceholder(text: "Paste a JWT (a Bearer prefix is fine)")
                }
            }
            .insetWell()
        }
    }

    // MARK: Validity

    @ViewBuilder
    private func validity(_ jwt: DecodedJWT) -> some View {
        let issued = jwt.date("iat")
        let notBefore = jwt.date("nbf")
        let expires = jwt.date("exp")

        if issued != nil || notBefore != nil || expires != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let status = TokenStatus(now: now, notBefore: notBefore, expires: expires)
                let allClaims: [(String, String, Date?)] = [
                    ("Issued", "iat", issued),
                    ("Not Before", "nbf", notBefore),
                    ("Expires", "exp", expires)
                ]
                let claims: [(String, String, Date)] = allClaims.compactMap { item in
                    guard let date = item.2 else { return nil }
                    return (item.0, item.1, date)
                }

                PanelSection("Validity") {
                    Label(status.label, systemImage: status.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(status.color)
                } content: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(headline(status: status, now: now, notBefore: notBefore, expires: expires))
                            .font(.system(size: 20, weight: .semibold))
                            .monospacedDigit()

                        if let start = issued ?? notBefore, let expires, expires > start {
                            CapsuleProgress(value: now.timeIntervalSince(start) / expires.timeIntervalSince(start),
                                            tint: status.color)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(claims.enumerated()), id: \.offset) { index, claim in
                                if index > 0 { Divider() }
                                ClaimRow(label: claim.0, claim: claim.1, date: claim.2)
                            }
                        }
                    }
                }
            }
        }
    }

    private func headline(status: TokenStatus, now: Date, notBefore: Date?, expires: Date?) -> String {
        switch status {
        case .expired:
            return "Expired \(Durations.string(now.timeIntervalSince(expires ?? now))) ago"
        case .notYetValid:
            return "Valid in \(Durations.string((notBefore ?? now).timeIntervalSince(now)))"
        case .valid:
            if let expires { return "Expires in \(Durations.string(expires.timeIntervalSince(now)))" }
            return "No expiry"
        }
    }

    // MARK: Decoded content

    private func decodedSection(_ jwt: DecodedJWT) -> some View {
        let text: String
        switch section {
        case .header: text = jwt.headerJSON
        case .payload: text = jwt.payloadJSON
        case .signature: text = jwt.signature
        }
        let size: CGFloat = 11
        let lineSpacing: CGFloat = 2
        let lineCount = CGFloat(text.split(separator: "\n", omittingEmptySubsequences: false).count)
        let contentHeight = lineCount * (TextStyle.lineHeight(TextStyle.mono(size)) + lineSpacing)
        let height: CGFloat = section == .signature ? 60 : min(max(contentHeight + 2, 40), 200)
        let styled = section == .signature
            ? TextStyle.plain(text, font: TextStyle.mono(size), color: .secondaryLabelColor,
                              paragraph: TextStyle.paragraph(lineBreak: .byCharWrapping))
            : JSONHighlighter.highlight(text, size: size, lineSpacing: lineSpacing)

        return PanelSection("Decoded") {
            IconButton(systemName: "doc.on.doc", help: "Copy \(section.title.lowercased())") {
                Clipboard.copy(text)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SegmentedPicker(selection: $section, compact: true)
                    Spacer()
                    if let alg = jwt.algorithm { Tag(text: alg, tint: .accentColor) }
                    if let typ = jwt.type { Tag(text: typ) }
                    if jwt.keyID != nil { Tag(text: "kid") }
                }

                SelectableText(attributedText: styled, scrollable: true)
                    .frame(height: height)

                Label("Decoded only. The signature is not verified.", systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ClaimRow: View {
    let label: String
    let claim: String
    let date: Date

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12))
            Text(claim)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            SelectableText(
                attributedText: TextStyle.plain(
                    date.formatted(date: .abbreviated, time: .standard),
                    font: font, color: .secondaryLabelColor,
                    paragraph: TextStyle.paragraph(alignment: .right, lineBreak: .byClipping)),
                copyLineOnClick: true
            )
            .frame(width: 200, height: TextStyle.lineHeight(font))
        }
        .padding(.vertical, 6)
    }
}
