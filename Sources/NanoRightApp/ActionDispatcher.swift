import AppKit
import Foundation
import NanoRightCore

@MainActor
final class ActionDispatcher {
    private unowned let appState: AppState
    private var fileInfoWindows: [NSWindow] = []
    private var customNewFileWindow: NSWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    func handle(_ command: ActionCommand) {
        let config = appState.config
        let lang = config.language

        switch command.kind {
        case .openSettings:
            NotificationCenter.default.post(name: .nanoRightOpenSettings, object: nil)

        case .newFile(let templateId):
            guard let dirPath = command.targetDirectory,
                  let template = config.newFileTemplates.first(where: { $0.id == templateId }) else { return }
            createNewFile(in: URL(fileURLWithPath: dirPath), template: template, customFileName: nil)

        case .customNewFile:
            guard let dirPath = command.targetDirectory else { return }
            showCustomNewFilePrompt(in: URL(fileURLWithPath: dirPath))

        case .moveTo(let destination):
            let sources = command.selectedPaths.map { URL(fileURLWithPath: $0) }
            let destURL = URL(fileURLWithPath: destination)
            runBackgroundFileOp {
                let moved = try FileOperations.moveItems(sources, to: destURL)
                await MainActor.run {
                    if !moved.isEmpty {
                        NSSound(named: "Tink")?.play()
                    }
                }
            }

        case .copyTo(let destination):
            let sources = command.selectedPaths.map { URL(fileURLWithPath: $0) }
            let destURL = URL(fileURLWithPath: destination)
            runBackgroundFileOp {
                let copied = try FileOperations.copyItems(sources, to: destURL)
                await MainActor.run {
                    if !copied.isEmpty {
                        NSSound(named: "Tink")?.play()
                    }
                }
            }

        case .openFolder(let path):
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.open(url)

        case .openInApp(let appPath, let isTerminal):
            AppLauncherService.open(
                appPath: appPath,
                isTerminal: isTerminal,
                targetDirectory: command.targetDirectory,
                selectedPaths: command.selectedPaths
            )

        case .pasteCutItems:
            guard let dirPath = command.targetDirectory else { return }
            performPasteCut(into: URL(fileURLWithPath: dirPath))

        case .cancelCut:
            performCancelCut()

        case .toolbox(let tool):
            handleToolbox(tool, command: command, config: config, language: lang)
        }
    }

    // MARK: - New File

    private func createNewFile(in directory: URL, template: NewFileTemplate, customFileName: String?) {
        let config = appState.config
        do {
            let createdURL = try TemplateGenerator.createFile(
                in: directory,
                template: template,
                customFileName: customFileName,
                templatesDirectory: appState.store.templatesDirectory,
                language: config.language
            )
            if config.newFilePlaySound {
                NSSound(named: "Pop")?.play()
            }
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])

            if config.newFileAutoOpen {
                NSWorkspace.shared.open(createdURL)
            } else if config.newFileAutoRename {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    _ = AppLauncherService.runAppleScript("""
                    tell application "Finder" to activate
                    tell application "System Events"
                        keystroke return
                    end tell
                    """)
                }
            }
        } catch {
            showErrorAlert(title: L10n.text("新建文件失败", "Failed to Create File", language: config.language), error: error)
        }
    }

    private func showCustomNewFilePrompt(in directory: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = CustomNewFilePanelController.makeWindow(
            directory: directory,
            language: appState.config.language
        ) { [weak self] filename in
            guard let self else { return }
            self.customNewFileWindow?.close()
            self.customNewFileWindow = nil
            guard let filename, !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let template = NewFileTemplate(name: filename, fileExtension: "")
            self.createNewFile(in: directory, template: template, customFileName: filename)
        }
        customNewFileWindow?.close()
        customNewFileWindow = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Cut / Paste / Cancel

    private func performCut(paths: [String]) {
        guard !paths.isEmpty else { return }
        // Restore any previously hidden cut files first
        let previous = appState.store.loadCutState()
        if previous.didHideFiles && !previous.paths.isEmpty {
            FileOperations.setHiddenFlag(false, for: previous.paths.map { URL(fileURLWithPath: $0) })
        }

        let shouldHide = appState.config.cutBehavior == .markHidden
        if shouldHide {
            FileOperations.setHiddenFlag(true, for: paths.map { URL(fileURLWithPath: $0) })
        }

        let newState = CutClipboardState(paths: paths, cutAt: Date(), didHideFiles: shouldHide)
        try? appState.store.saveCutState(newState)
        appState.cutCount = paths.count
    }

    private func performPasteCut(into destination: URL) {
        let state = appState.store.loadCutState()
        guard !state.isEmpty else { return }
        let urls = state.paths.map { URL(fileURLWithPath: $0) }
        if state.didHideFiles {
            FileOperations.setHiddenFlag(false, for: urls)
        }
        runBackgroundFileOp {
            let moved = try FileOperations.moveItems(urls, to: destination)
            await MainActor.run {
                try? self.appState.store.clearCutState()
                self.appState.cutCount = 0
                if !moved.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(moved)
                }
            }
        }
    }

    private func performCancelCut() {
        let state = appState.store.loadCutState()
        if state.didHideFiles && !state.paths.isEmpty {
            FileOperations.setHiddenFlag(false, for: state.paths.map { URL(fileURLWithPath: $0) })
        }
        try? appState.store.clearCutState()
        appState.cutCount = 0
    }

    // MARK: - Toolbox Dispatch

    private func handleToolbox(
        _ tool: ToolboxActionKind,
        command: ActionCommand,
        config: AppConfig,
        language lang: AppLanguage
    ) {
        let selectedURLs = command.selectedPaths.map { URL(fileURLWithPath: $0) }
        let effectivePaths = !command.selectedPaths.isEmpty
            ? command.selectedPaths
            : (command.targetDirectory.map { [$0] } ?? [])

        switch tool {
        case .copyPath:
            let text = FileOperations.formatPaths(effectivePaths, style: config.copyPathStyle)
            copyToPasteboard(text)

        case .copyName:
            let text = FileOperations.formatNames(effectivePaths)
            copyToPasteboard(text)

        case .cut:
            performCut(paths: command.selectedPaths)

        case .permanentDelete:
            guard !selectedURLs.isEmpty else { return }
            if config.deleteConfirmation == .askConfirmation {
                confirmAndDelete(selectedURLs, language: lang)
            } else {
                runBackgroundFileOp {
                    try FileOperations.permanentDelete(selectedURLs)
                }
            }

        case .toggleHiddenFiles:
            toggleFinderHiddenFiles()

        case .fileInfoAndHash:
            guard let targetPath = effectivePaths.first else { return }
            showFileInfoWindow(for: URL(fileURLWithPath: targetPath))

        case .compressZip:
            guard !selectedURLs.isEmpty else { return }
            runBackgroundFileOp {
                let zipURL = try FileOperations.compressToZip(selectedURLs)
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                }
            }

        case .newFolderFromFile:
            guard !selectedURLs.isEmpty else { return }
            runBackgroundFileOp {
                let folder = try FileOperations.createFolderFromItems(selectedURLs)
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
            }

        case .dissolveFolder:
            let dirs = selectedURLs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            guard !dirs.isEmpty else { return }
            runBackgroundFileOp {
                var allMoved: [URL] = []
                for dir in dirs {
                    let moved = try FileOperations.dissolveFolder(dir, trashEmptyFolder: true)
                    allMoved.append(contentsOf: moved)
                }
                await MainActor.run {
                    if !allMoved.isEmpty {
                        NSWorkspace.shared.activateFileViewerSelecting(allMoved)
                    }
                }
            }

        case .aliasToDesktop:
            guard !selectedURLs.isEmpty else { return }
            runBackgroundFileOp {
                let aliases = try FileOperations.createDesktopAlias(for: selectedURLs)
                await MainActor.run {
                    if !aliases.isEmpty {
                        NSWorkspace.shared.activateFileViewerSelecting(aliases)
                    }
                }
            }

        case .addToCommonFolders:
            let dirs = effectivePaths.compactMap { path -> URL? in
                let url = URL(fileURLWithPath: path)
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return isDir ? url : nil
            }
            for dir in dirs {
                appState.addCommonFolder(url: dir)
            }

        case .grantWritePermission:
            guard !selectedURLs.isEmpty else { return }
            runBackgroundFileOp {
                try FileOperations.grantWritePermission(for: selectedURLs)
                await MainActor.run {
                    _ = NSSound(named: "Tink")?.play()
                }
            }

        case .airDrop:
            guard !selectedURLs.isEmpty else { return }
            NSApp.activate(ignoringOtherApps: true)
            if let service = NSSharingService(named: .sendViaAirDrop) {
                service.perform(withItems: selectedURLs)
            }

        case .setWallpaper:
            guard let imageURL = selectedURLs.first, let screen = NSScreen.main else { return }
            do {
                try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: [:])
            } catch {
                showErrorAlert(title: L10n.text("设置墙纸失败", "Failed to Set Wallpaper", language: lang), error: error)
            }

        case .printFile:
            guard !selectedURLs.isEmpty else { return }
            for url in selectedURLs {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/lpr")
                proc.arguments = [url.path]
                try? proc.run()
            }

        case .lockScreen:
            lockMacScreen()
        }
    }

    // MARK: - Helpers

    private func copyToPasteboard(_ string: String) {
        guard !string.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    private func confirmAndDelete(_ urls: [URL], language lang: AppLanguage) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.text(
            "确定要彻底删除这 \(urls.count) 个项目吗？",
            "Permanently delete \(urls.count) item(s)?",
            language: lang
        )
        let preview = urls.prefix(5).map(\.lastPathComponent).joined(separator: "\n")
        let suffix = urls.count > 5 ? "\n..." : ""
        alert.informativeText = L10n.text(
            "此操作将跳过废纸篓且无法撤销：\n\(preview)\(suffix)",
            "This bypasses Trash and cannot be undone:\n\(preview)\(suffix)",
            language: lang
        )
        alert.addButton(withTitle: L10n.text("彻底删除", "Delete Permanently", language: lang))
        alert.addButton(withTitle: L10n.text("取消", "Cancel", language: lang))

        if alert.runModal() == .alertFirstButtonReturn {
            runBackgroundFileOp {
                try FileOperations.permanentDelete(urls)
            }
        }
    }

    private func toggleFinderHiddenFiles() {
        let current = readFinderShowAllFiles()
        let next = !current
        let writeProc = Process()
        writeProc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        writeProc.arguments = ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", next ? "true" : "false"]
        try? writeProc.run()
        writeProc.waitUntilExit()

        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProc.arguments = ["Finder"]
        try? killProc.run()
    }

    private func readFinderShowAllFiles() -> Bool {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["read", "com.apple.finder", "AppleShowAllFiles"]
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return str == "1" || str == "true" || str == "yes"
        } catch {
            return false
        }
    }

    private func lockMacScreen() {
        let cgSession = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        if FileManager.default.isExecutableFile(atPath: cgSession) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: cgSession)
            proc.arguments = ["-suspend"]
            try? proc.run()
        } else {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            proc.arguments = ["displaysleepnow"]
            try? proc.run()
        }
    }

    private func showFileInfoWindow(for url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let window = FileInfoWindowController.makeWindow(url: url, language: appState.config.language)
        fileInfoWindows.removeAll { !$0.isVisible }
        fileInfoWindows.append(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func runBackgroundFileOp(_ work: @escaping () async throws -> Void) {
        Task.detached(priority: .userInitiated) {
            do {
                try await work()
            } catch {
                await MainActor.run {
                    let lang = self.appState.config.language
                    self.showErrorAlert(title: L10n.text("操作失败", "Operation Failed", language: lang), error: error)
                }
            }
        }
    }

    private func showErrorAlert(title: String, error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

extension Notification.Name {
    static let nanoRightOpenSettings = Notification.Name("com.nanoright.openSettingsWindow")
}
