import Foundation

enum BackgroundAudioMixMode: String, CaseIterable, Equatable {
    case uploadedOnly
    case videoAndUploaded

    var title: String {
        switch self {
        case .uploadedOnly: return "Uploaded Audio Only"
        case .videoAndUploaded: return "Video + Uploaded Audio"
        }
    }
}

enum BackgroundAudioFilePolicy {
    static let supportedExtensions: Set<String> = ["mp3", "m4a"]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

enum BackgroundAudioSelectionError: LocalizedError, Equatable {
    case unsupportedFormat
    case missingFile
    case bookmarkCreationFailed(String)
    case bookmarkResolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Choose an MP3 or M4A audio file."
        case .missingFile:
            return "The selected audio file is unavailable."
        case .bookmarkCreationFailed(let message), .bookmarkResolutionFailed(let message):
            return message
        }
    }
}

struct BackgroundAudioBookmarkResolution: Equatable {
    let url: URL
    let isStale: Bool
}

protocol BackgroundAudioBookmarkCoding {
    func bookmarkData(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> BackgroundAudioBookmarkResolution
}

struct SecurityScopedBackgroundAudioBookmarkCodec: BackgroundAudioBookmarkCoding {
    func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope],
                             includingResourceValuesForKeys: nil,
                             relativeTo: nil)
    }

    func resolve(_ data: Data) throws -> BackgroundAudioBookmarkResolution {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data,
                          options: [.withSecurityScope],
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        return BackgroundAudioBookmarkResolution(url: url, isStale: isStale)
    }
}

enum BackgroundAudioSelection {
    case none
    case available(URL)
    case unavailable(displayName: String, reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var displayName: String? {
        switch self {
        case .none: return nil
        case .available(let url): return url.lastPathComponent
        case .unavailable(let displayName, _): return displayName
        }
    }
}

struct BackgroundAudioSettingsSnapshot {
    let selection: BackgroundAudioSelection
    let mixMode: BackgroundAudioMixMode
    let volume: Double
}

final class BackgroundAudioSettingsStore {
    static let shared = BackgroundAudioSettingsStore()

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let bookmarkCodec: BackgroundAudioBookmarkCoding
    private let fileExists: (String) -> Bool

    init(defaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default,
         bookmarkCodec: BackgroundAudioBookmarkCoding = SecurityScopedBackgroundAudioBookmarkCodec(),
         fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:)) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.bookmarkCodec = bookmarkCodec
        self.fileExists = fileExists
    }

    func snapshot() -> BackgroundAudioSettingsSnapshot {
        BackgroundAudioSettingsSnapshot(selection: selection(),
                                        mixMode: mixMode(),
                                        volume: volume())
    }

    func select(_ url: URL) throws {
        guard BackgroundAudioFilePolicy.isSupported(url) else {
            throw BackgroundAudioSelectionError.unsupportedFormat
        }
        guard fileExists(url.path) else {
            throw BackgroundAudioSelectionError.missingFile
        }
        do {
            let data = try bookmarkCodec.bookmarkData(for: url)
            defaults.set(data, forKey: SettingsDefaultsRegistry.Keys.backgroundAudioBookmark)
            defaults.set(url.lastPathComponent, forKey: SettingsDefaultsRegistry.Keys.backgroundAudioDisplayName)
            notificationCenter.post(name: .skimPlusSettingsChanged, object: self)
        } catch {
            throw BackgroundAudioSelectionError.bookmarkCreationFailed(error.localizedDescription)
        }
    }

    func clearSelection() {
        defaults.removeObject(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioBookmark)
        defaults.removeObject(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioDisplayName)
        notificationCenter.post(name: .skimPlusSettingsChanged, object: self)
    }

    func setMixMode(_ mode: BackgroundAudioMixMode) {
        let key = SettingsDefaultsRegistry.Keys.backgroundAudioMixMode
        guard defaults.string(forKey: key) != mode.rawValue else { return }
        defaults.set(mode.rawValue, forKey: key)
        notificationCenter.post(name: .skimPlusSettingsChanged, object: self)
    }

    func setVolume(_ value: Double) {
        let normalized = SettingsDefaultsRegistry.validatedBackgroundAudioVolume(value)
        let key = SettingsDefaultsRegistry.Keys.backgroundAudioVolume
        guard abs(defaults.double(forKey: key) - normalized) > 0.0001 else { return }
        defaults.set(normalized, forKey: key)
        notificationCenter.post(name: .skimPlusSettingsChanged, object: self)
    }

    private func mixMode() -> BackgroundAudioMixMode {
        let value = defaults.string(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioMixMode)
            ?? SettingsDefaultsRegistry.Defaults.backgroundAudioMixMode
        let mode = BackgroundAudioMixMode(rawValue: value) ?? .uploadedOnly
        if mode.rawValue != value {
            defaults.set(mode.rawValue, forKey: SettingsDefaultsRegistry.Keys.backgroundAudioMixMode)
        }
        return mode
    }

    private func volume() -> Double {
        let raw = defaults.object(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioVolume) == nil
            ? SettingsDefaultsRegistry.Defaults.backgroundAudioVolume
            : defaults.double(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioVolume)
        let normalized = SettingsDefaultsRegistry.validatedBackgroundAudioVolume(raw)
        if raw != normalized {
            defaults.set(normalized, forKey: SettingsDefaultsRegistry.Keys.backgroundAudioVolume)
        }
        return normalized
    }

    private func selection() -> BackgroundAudioSelection {
        let name = defaults.string(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioDisplayName)
            ?? "Background audio"
        guard let data = defaults.data(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioBookmark) else {
            return defaults.string(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioDisplayName) == nil
                ? .none
                : .unavailable(displayName: name, reason: "Select the file again or clear it.")
        }

        do {
            let resolution = try bookmarkCodec.resolve(data)
            let url = resolution.url
            guard BackgroundAudioFilePolicy.isSupported(url) else {
                return .unavailable(displayName: name, reason: BackgroundAudioSelectionError.unsupportedFormat.localizedDescription)
            }
            guard fileExists(url.path) else {
                return .unavailable(displayName: name, reason: BackgroundAudioSelectionError.missingFile.localizedDescription)
            }
            if resolution.isStale,
               let refreshed = try? bookmarkCodec.bookmarkData(for: url) {
                defaults.set(refreshed, forKey: SettingsDefaultsRegistry.Keys.backgroundAudioBookmark)
            }
            defaults.set(url.lastPathComponent, forKey: SettingsDefaultsRegistry.Keys.backgroundAudioDisplayName)
            return .available(url)
        } catch {
            return .unavailable(displayName: name,
                                reason: BackgroundAudioSelectionError.bookmarkResolutionFailed(error.localizedDescription).localizedDescription)
        }
    }
}

enum VideoAudioPolicy {
    static func effectiveVolume(storedVolume: Int32,
                                muted: Bool,
                                mixMode: BackgroundAudioMixMode,
                                backgroundAudioIsActive: Bool) -> Int32 {
        let clamped = Int32(max(0, min(VideoVolumeMeterPresentation.maximumVolume, Int(storedVolume))))
        if muted { return 0 }
        if mixMode == .uploadedOnly && backgroundAudioIsActive { return 0 }
        return clamped
    }
}
