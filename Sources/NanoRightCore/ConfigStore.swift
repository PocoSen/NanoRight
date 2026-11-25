import Foundation
import Darwin

public final class ConfigStore {
    public static let configChangedNotification = "com.nanoright.configChanged"
    public static let cutStateChangedNotification = "com.nanoright.cutStateChanged"
    public static let pendingCommandNotification = "com.nanoright.pendingCommand"

    public let baseDirectory: URL
    public let configFileURL: URL
    public let cutStateFileURL: URL
    public let templatesDirectory: URL
    public let iconsDirectory: URL
    public let pendingCommandsDirectory: URL

    private var lastConfigMTime: Date?
    private var lastCutStateMTime: Date?
    private var cachedConfig: AppConfig?
    private var cachedCutState: CutClipboardState?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Resolves the real user home directory via POSIX `getpwuid` so both the non-sandboxed
    /// host app and the sandboxed FinderSync extension resolve the exact same path.
    public static var realHomePath: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    public static var defaultBaseDirectory: URL {
        URL(fileURLWithPath: realHomePath)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("NanoRight", isDirectory: true)
    }

    public init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? Self.defaultBaseDirectory
        self.baseDirectory = base
        self.configFileURL = base.appendingPathComponent("config.json")
        self.cutStateFileURL = base.appendingPathComponent("cut-state.json")
        self.templatesDirectory = base.appendingPathComponent("templates", isDirectory: true)
        self.iconsDirectory = base.appendingPathComponent("icons", isDirectory: true)
        self.pendingCommandsDirectory = base.appendingPathComponent("pending-commands", isDirectory: true)
    }

    public func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: pendingCommandsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Config

    public func loadConfig() -> AppConfig {
        if let data = try? Data(contentsOf: configFileURL),
           let decoded = try? decoder.decode(AppConfig.self, from: data) {
            cachedConfig = decoded
            lastConfigMTime = modificationDate(of: configFileURL)
            return decoded
        }
        let defaults = AppConfig.defaultConfig()
        cachedConfig = defaults
        return defaults
    }

    public func reloadConfigIfNeeded() -> AppConfig {
        let mtime = modificationDate(of: configFileURL)
        if let cached = cachedConfig, mtime == lastConfigMTime {
            return cached
        }
        return loadConfig()
    }

    public func saveConfig(_ config: AppConfig, notify: Bool = true) throws {
        try ensureDirectoriesExist()
        let data = try encoder.encode(config)
        try data.write(to: configFileURL, options: .atomic)
        cachedConfig = config
        lastConfigMTime = modificationDate(of: configFileURL)
        if notify {
            Self.postDarwinNotification(Self.configChangedNotification)
        }
    }

    // MARK: - Cut Clipboard State

    public func loadCutState() -> CutClipboardState {
        if let data = try? Data(contentsOf: cutStateFileURL),
           let decoded = try? decoder.decode(CutClipboardState.self, from: data) {
            cachedCutState = decoded
            lastCutStateMTime = modificationDate(of: cutStateFileURL)
            return decoded
        }
        let empty = CutClipboardState()
        cachedCutState = empty
        return empty
    }

    public func reloadCutStateIfNeeded() -> CutClipboardState {
        let mtime = modificationDate(of: cutStateFileURL)
        if let cached = cachedCutState, mtime == lastCutStateMTime {
            return cached
        }
        return loadCutState()
    }

    public func saveCutState(_ state: CutClipboardState, notify: Bool = true) throws {
        try ensureDirectoriesExist()
        let data = try encoder.encode(state)
        try data.write(to: cutStateFileURL, options: .atomic)
        cachedCutState = state
        lastCutStateMTime = modificationDate(of: cutStateFileURL)
        if notify {
            Self.postDarwinNotification(Self.cutStateChangedNotification)
        }
    }

    public func clearCutState(notify: Bool = true) throws {
        try saveCutState(CutClipboardState(), notify: notify)
    }

    // MARK: - Pending Command Queue (Sandbox-Safe Extension -> Host IPC)

    public func enqueueCommand(_ command: ActionCommand, notify: Bool = true) throws {
        try ensureDirectoriesExist()
        let fileURL = pendingCommandsDirectory.appendingPathComponent("\(command.id.uuidString).json")
        let data = try encoder.encode(command)
        try data.write(to: fileURL, options: .atomic)
        if notify {
            Self.postDarwinNotification(Self.pendingCommandNotification)
        }
    }

    public func drainPendingCommands() -> [ActionCommand] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: pendingCommandsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sorted = urls.filter { $0.pathExtension == "json" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da < db
        }

        var commands: [ActionCommand] = []
        for url in sorted {
            if let data = try? Data(contentsOf: url),
               let cmd = try? decoder.decode(ActionCommand.self, from: data) {
                commands.append(cmd)
            }
            try? fm.removeItem(at: url)
        }
        return commands
    }

    // MARK: - Icon Cache Paths

    public func iconFileURL(forKey key: String) -> URL {
        let safeKey = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return iconsDirectory.appendingPathComponent("\(safeKey).png")
    }

    // MARK: - Darwin Notifications

    public static func postDarwinNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    private func modificationDate(of url: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }
}
