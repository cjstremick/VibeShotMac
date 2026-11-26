import AppKit

enum RecordingDestination: String, CaseIterable {
    case ask
    case folder
    case clipboard

    var title: String {
        switch self {
        case .ask: return "Ask where to save"
        case .folder: return "Save to a folder"
        case .clipboard: return "Copy to clipboard"
        }
    }
}

/// User preferences for recording. `RecordingSettings.shared` is used by the app;
/// the injectable initializer keeps the type testable without touching the real
/// defaults.
final class RecordingSettings {
    static let shared = RecordingSettings()

    private enum Key {
        static let destination = "RecordingDestination"
        static let folderBookmark = "RecordingFolderBookmark"
        static let countdown = "RecordingCountdownSeconds"
        static let showPointerActivity = "RecordingShowPointerActivity"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var destination: RecordingDestination {
        get { RecordingDestination(rawValue: defaults.string(forKey: Key.destination) ?? "") ?? .ask }
        set { defaults.set(newValue.rawValue, forKey: Key.destination) }
    }

    /// Delay before recording starts. Supported values are 0, 3, 5 and 10 seconds.
    var countdownSeconds: Int {
        get {
            let value = defaults.integer(forKey: Key.countdown)
            return [0, 3, 5, 10].contains(value) ? value : 0
        }
        set {
            defaults.set([0, 3, 5, 10].contains(newValue) ? newValue : 0, forKey: Key.countdown)
        }
    }

    /// Includes the real pointer plus click ripples and scroll indicators in the
    /// recording. Off by default.
    var showPointerActivity: Bool {
        get { defaults.bool(forKey: Key.showPointerActivity) }
        set { defaults.set(newValue, forKey: Key.showPointerActivity) }
    }

    var hasFolder: Bool { defaults.data(forKey: Key.folderBookmark) != nil }

    /// Stores a security-scoped bookmark so a sandboxed app can write to the
    /// folder across launches.
    func setFolder(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        defaults.set(data, forKey: Key.folderBookmark)
    }

    func folderURL() -> URL? {
        guard let data = defaults.data(forKey: Key.folderBookmark) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let refreshed = try? url.bookmarkData(options: .withSecurityScope,
                                                        includingResourceValuesForKeys: nil,
                                                        relativeTo: nil) {
            defaults.set(refreshed, forKey: Key.folderBookmark)
        }
        return url
    }

    func clearFolder() {
        defaults.removeObject(forKey: Key.folderBookmark)
    }

    /// A readable, sortable default name such as `Screen Recording 2026-11-26 at 14.32.05.mp4`.
    static func recordingFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screen Recording \(formatter.string(from: date)).mp4"
    }
}

/// Files the app keeps itself: clipboard recordings and recovered saves.
enum RecordingStorage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("VibeShot/Recordings", isDirectory: true)
    }

    static func uniqueDestination(in directory: URL, name: String) -> URL {
        let fileManager = FileManager.default
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index).\(ext)")
            index += 1
        }
        return candidate
    }
}
