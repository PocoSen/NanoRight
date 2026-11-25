import AppKit
import FinderSync
import Foundation
import NanoRightCore
import ServiceManagement

enum ExtensionStatus: Equatable {
    case enabled
    case disabled
    case notRegistered
    case unknown
}

@MainActor
final class AppState: ObservableObject {
    let store: ConfigStore
    @Published var config: AppConfig
    @Published var extensionStatus: ExtensionStatus = .unknown
    @Published var cutCount: Int = 0
    @Published var statusBannerMessage: String?

    var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        return path == "/Applications/NanoRight.app" || path.hasPrefix("/Applications/")
    }

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
        self.config = store.loadConfig()
        self.cutCount = store.loadCutState().paths.count

        if !FileManager.default.fileExists(atPath: store.configFileURL.path) {
            save()
        } else {
            IconCacheService.syncIcons(for: config, store: store)
        }

        bootstrapRegistrationAndCheckStatus()
    }

    func save() {
        do {
            try store.saveConfig(config, notify: true)
            IconCacheService.syncIcons(for: config, store: store)
            NotificationCenter.default.post(name: .nanoRightMenuBarPreferenceChanged, object: nil)
        } catch {
            statusBannerMessage = error.localizedDescription
        }
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        config.launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusBannerMessage = L10n.text(
                "开机自启请先点击上方「一键安装到应用程序」后再开启。",
                "Install NanoRight to /Applications first to enable Launch at Login.",
                language: config.language
            )
        }
        save()
    }

    func addCommonFolder(url: URL) {
        let normalized = abbreviateHomePath(url.path)
        if config.commonFolders.contains(where: { $0.resolvedURL().standardizedFileURL == url.standardizedFileURL }) {
            return
        }
        config.commonFolders.append(FolderItem(name: url.lastPathComponent, path: normalized))
        save()
    }

    func addSendToFolder(url: URL) {
        let normalized = abbreviateHomePath(url.path)
        if config.sendToFolders.contains(where: { $0.resolvedURL().standardizedFileURL == url.standardizedFileURL }) {
            return
        }
        config.sendToFolders.append(FolderItem(name: url.lastPathComponent, path: normalized))
        save()
    }

    func addCustomTemplateFile(from sourceURL: URL) {
        do {
            try store.ensureDirectoriesExist()
            let ext = sourceURL.pathExtension
            let id = UUID()
            let storedFilename = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
            let destURL = store.templatesDirectory.appendingPathComponent(storedFilename)
            try FileManager.default.copyItem(at: sourceURL, to: destURL)

            let name = sourceURL.deletingPathExtension().lastPathComponent
            let template = NewFileTemplate(
                id: id,
                name: name.isEmpty ? sourceURL.lastPathComponent : name,
                fileExtension: ext,
                isEnabled: true,
                showInMainMenu: false,
                isCustomPrompt: false,
                customTemplateFilename: storedFilename,
                sfSymbol: "doc.fill"
            )
            config.newFileTemplates.append(template)
            save()
        } catch {
            statusBannerMessage = error.localizedDescription
        }
    }

    func removeNewFileTemplates(ids: Set<UUID>) {
        for template in config.newFileTemplates where ids.contains(template.id) {
            if let filename = template.customTemplateFilename {
                try? FileManager.default.removeItem(at: store.templatesDirectory.appendingPathComponent(filename))
            }
        }
        config.newFileTemplates.removeAll { ids.contains($0.id) }
        save()
    }

    func addAppLauncher(from appURL: URL) {
        if config.appLaunchers.contains(where: { $0.appPath == appURL.path }) { return }
        let name = appURL.deletingPathExtension().lastPathComponent
        let item = AppLauncherItem(
            name: name,
            appPath: appURL.path,
            isEnabled: true,
            isTerminal: AppLauncherService.isLikelyTerminal(appPath: appURL.path)
        )
        config.appLaunchers.append(item)
        save()
    }

    func abbreviateHomePath(_ path: String) -> String {
        let home = ConfigStore.realHomePath
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~/" + String(path.dropFirst(home.count + 1))
        }
        return path
    }

    // MARK: - Self-Registration & One-Click Install

    func bootstrapRegistrationAndCheckStatus() {
        let bundlePath = Bundle.main.bundleURL.path
        Task.detached(priority: .utility) {
            Self.registerAppAndPlugin(bundlePath: bundlePath)
            let status = Self.detectExtensionStatus()
            await MainActor.run {
                self.extensionStatus = status
            }
        }
    }

    func refreshExtensionStatus() {
        Task.detached(priority: .utility) {
            let status = Self.detectExtensionStatus()
            await MainActor.run {
                self.extensionStatus = status
            }
        }
    }

    func installToApplicationsAndRelaunch() {
        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        guard currentURL.pathExtension == "app" else {
            statusBannerMessage = L10n.text(
                "当前不是从 .app 应用包运行，请打开编译好的 NanoRight.app。",
                "Not running from a .app bundle. Please launch NanoRight.app.",
                language: config.language
            )
            return
        }

        let destURL = URL(fileURLWithPath: "/Applications/NanoRight.app")
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: currentURL, to: destURL)
            Self.clearQuarantine(path: destURL.path)
            Self.registerAppAndPlugin(bundlePath: destURL.path)

            let openConfig = NSWorkspace.OpenConfiguration()
            openConfig.activates = true
            openConfig.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: destURL, configuration: openConfig) { _, error in
                if error == nil {
                    DispatchQueue.main.async {
                        NSApp.terminate(nil)
                    }
                }
            }
        } catch {
            statusBannerMessage = L10n.text(
                "自动拷贝到 /Applications 失败（\(error.localizedDescription)），请手动将 NanoRight.app 拖入「应用程序」文件夹。",
                "Could not copy to /Applications (\(error.localizedDescription)). Please drag NanoRight.app into /Applications manually.",
                language: config.language
            )
        }
    }

    private nonisolated static func clearQuarantine(path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-dr", "com.apple.quarantine", path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
    }

    private nonisolated static func registerAppAndPlugin(bundlePath: String) {
        guard bundlePath.hasSuffix(".app") else { return }

        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if FileManager.default.isExecutableFile(atPath: lsregister) {
            let ls = Process()
            ls.executableURL = URL(fileURLWithPath: lsregister)
            ls.arguments = ["-f", bundlePath]
            ls.standardOutput = Pipe()
            ls.standardError = Pipe()
            try? ls.run()
            ls.waitUntilExit()
        }

        let appexPath = (bundlePath as NSString).appendingPathComponent("Contents/PlugIns/NanoRightFinder.appex")
        if FileManager.default.fileExists(atPath: appexPath) {
            let addProc = Process()
            addProc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            addProc.arguments = ["-a", appexPath]
            addProc.standardOutput = Pipe()
            addProc.standardError = Pipe()
            try? addProc.run()
            addProc.waitUntilExit()

            let enableProc = Process()
            enableProc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            enableProc.arguments = ["-e", "use", "-i", "com.nanoright.app.finder"]
            enableProc.standardOutput = Pipe()
            enableProc.standardError = Pipe()
            try? enableProc.run()
            enableProc.waitUntilExit()
        }
    }

    private nonisolated static func detectExtensionStatus() -> ExtensionStatus {
        if FIFinderSyncController.isExtensionEnabled {
            return .enabled
        }
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-m", "-v", "-i", "com.nanoright.app.finder"]
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .notRegistered }
            if trimmed.hasPrefix("+") { return .enabled }
            return .disabled
        } catch {
            return .disabled
        }
    }

    func openFinderExtensionsSettings() {
        // Official Apple FinderSync API (works on macOS 14 Sonoma & macOS 15 Sequoia)
        FIFinderSyncController.showExtensionManagementInterface()

        // Fallback deep-link for macOS 13–15 Login Items & Extensions pane if needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
               let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func restartFinder() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        proc.arguments = ["Finder"]
        try? proc.run()
    }
}

extension Notification.Name {
    static let nanoRightMenuBarPreferenceChanged = Notification.Name("com.nanoright.menuBarPreferenceChanged")
}
