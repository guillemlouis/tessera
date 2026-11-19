import AppKit
import Combine

struct GUIDEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let value: String
    let createdAt: Date
}

/// Mirrors .NET Guid.ToString() format specifiers.
enum GUIDFormat: String, CaseIterable, Identifiable, SegmentOption {
    case d, n, b, p

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    func render(_ uuid: UUID, uppercase: Bool) -> String {
        let base = uppercase ? uuid.uuidString.uppercased() : uuid.uuidString.lowercased()
        switch self {
        case .d: return base
        case .n: return base.replacingOccurrences(of: "-", with: "")
        case .b: return "{\(base)}"
        case .p: return "(\(base))"
        }
    }
}

enum GUIDExtractor {
    private static let regex = try! NSRegularExpression(
        pattern: "[{(]?[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}[})]?"
    )

    /// Keeps only the GUIDs in a selection (one per line). Returns the text unchanged if none is complete.
    static func extract(_ text: String) -> String {
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
        return matches.isEmpty ? text : matches.joined(separator: "\n")
    }
}

enum LetterCase: String, CaseIterable, Identifiable, SegmentOption {
    case lower, upper

    var id: String { rawValue }
    var title: String { self == .lower ? "abc" : "ABC" }
}

enum AutoClear: String, CaseIterable, Identifiable {
    case never, onQuit, hour, day, week

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: return "Never"
        case .onQuit: return "When Tessera quits"
        case .hour: return "After 1 hour"
        case .day: return "After 1 day"
        case .week: return "After 7 days"
        }
    }

    var shortLabel: String {
        switch self {
        case .never: return "keep"
        case .onQuit: return "on quit"
        case .hour: return "1h"
        case .day: return "1d"
        case .week: return "7d"
        }
    }

    var maxAge: TimeInterval? {
        switch self {
        case .hour: return 3_600
        case .day: return 86_400
        case .week: return 604_800
        case .never, .onQuit: return nil
        }
    }
}

final class GUIDStore: ObservableObject {
    @Published private(set) var history: [GUIDEntry] = []
    @Published private(set) var current: String?

    @Published var format: GUIDFormat {
        didSet { defaults.set(format.rawValue, forKey: Keys.format) }
    }
    @Published var letterCase: LetterCase {
        didSet { defaults.set(letterCase.rawValue, forKey: Keys.letterCase) }
    }
    @Published var autoClear: AutoClear {
        didSet {
            defaults.set(autoClear.rawValue, forKey: Keys.autoClear)
            pruneExpired()
        }
    }

    private let defaults = UserDefaults.standard
    private let maxEntries = 200
    private var pruneTimer: Timer?
    private var terminateObserver: NSObjectProtocol?

    private enum Keys {
        static let history = "guid.history"
        static let format = "guid.format"
        static let letterCase = "guid.letterCase"
        static let autoClear = "guid.autoClear"
    }

    init() {
        let stored = UserDefaults.standard
        format = GUIDFormat(rawValue: stored.string(forKey: Keys.format) ?? "") ?? .d
        letterCase = LetterCase(rawValue: stored.string(forKey: Keys.letterCase) ?? "") ?? .lower
        autoClear = AutoClear(rawValue: stored.string(forKey: Keys.autoClear) ?? "") ?? .day

        if let data = stored.data(forKey: Keys.history),
           let saved = try? JSONDecoder().decode([GUIDEntry].self, from: data) {
            history = saved
        }
        // "On quit" also clears at launch, which covers crashes and force quits.
        if autoClear == .onQuit { history = [] }
        pruneExpired()
        persist()

        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pruneExpired()
        }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.autoClear == .onQuit else { return }
            self.clearHistory()
        }
    }

    deinit {
        pruneTimer?.invalidate()
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }

    // MARK: Actions

    func generate() {
        let value = format.render(UUID(), uppercase: letterCase == .upper)
        current = value
        history.insert(GUIDEntry(id: UUID(), value: value, createdAt: Date()), at: 0)
        if history.count > maxEntries {
            history.removeLast(history.count - maxEntries)
        }
        persist()
        Clipboard.copy(value)
    }

    /// Empties the generator display. History is not affected.
    func clearCurrent() {
        current = nil
    }

    /// Highlights a history value as current after it was copied from the list.
    func markCurrent(_ value: String) {
        if history.contains(where: { $0.value == value }) {
            current = value
        }
    }

    func clearHistory() {
        history = []
        current = nil
        persist()
    }

    func pruneExpired() {
        guard let maxAge = autoClear.maxAge else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        let kept = history.filter { $0.createdAt >= cutoff }
        guard kept.count != history.count else { return }
        history = kept
        if let current, !kept.contains(where: { $0.value == current }) {
            self.current = nil
        }
        persist()
    }

    // MARK: Private

    private func persist() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Keys.history)
        }
    }
}
