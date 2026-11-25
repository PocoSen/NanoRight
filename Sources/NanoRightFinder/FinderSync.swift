import AppKit
import FinderSync
import Foundation

@objc(NanoRightFinderSync)
final class NanoRightFinderSync: FIFinderSync {
    private let configStore = ConfigStore()
    private var config: AppConfig
    private var cutState: CutClipboardState
    private var iconMemoryCache: [String: NSImage] = [:]
    /// FIFinderSync strips `NSMenuItem.representedObject` across Finder's XPC boundary,
    /// preserving `tag`. Store commands keyed by `tag` for reliable lookup on click.
    private var menuCommandsByTag: [Int: ActionCommand] = [:]
    private var nextMenuTag: Int = 1

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp", "tiff", "tif", "bmp", "gif"
    ]

    override init() {
        self.config = configStore.loadConfig()
        self.cutState = configStore.loadCutState()
        super.init()

        updateMonitoredDirectories()
        registerObservers()
    }

    deinit {
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(darwinCenter, Unmanaged.passUnretained(self).toOpaque())
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Observers & Scope

    private func registerObservers() {
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            darwinCenter,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let instance = Unmanaged<NanoRightFinderSync>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    instance.reloadFromDiskAndUpdateScope()
                }
            },
            ConfigStore.configChangedNotification as CFString,
            nil,
            .deliverImmediately
        )

        CFNotificationCenterAddObserver(
            darwinCenter,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let instance = Unmanaged<NanoRightFinderSync>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    instance.cutState = instance.configStore.loadCutState()
                }
            },
            ConfigStore.cutStateChangedNotification as CFString,
            nil,
            .deliverImmediately
        )

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspace.didMountNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspace.didUnmountNotification, object: nil)
    }

    @objc private func volumesChanged(_ notification: Notification) {
        if config.scopeMode == .allDisks {
            updateMonitoredDirectories()
        }
    }

    private func reloadFromDiskAndUpdateScope() {
        let previousScope = (config.scopeMode, config.customScopePaths)
        config = configStore.loadConfig()
        cutState = configStore.loadCutState()
        iconMemoryCache.removeAll()
        if previousScope.0 != config.scopeMode || previousScope.1 != config.customScopePaths {
            updateMonitoredDirectories()
        }
    }

    private func updateMonitoredDirectories() {
        var urls = Set<URL>()
        switch config.scopeMode {
        case .allDisks:
            urls.insert(URL(fileURLWithPath: "/"))
            if let volumes = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: nil,
                options: [.skipHiddenVolumes]
            ) {
                for volume in volumes {
                    urls.insert(volume)
                }
            }
        case .homeDirectory:
            urls.insert(URL(fileURLWithPath: ConfigStore.realHomePath))
        case .custom:
            for raw in config.customScopePaths {
                let item = FolderItem(name: "", path: raw)
                urls.insert(item.resolvedURL())
            }
            if urls.isEmpty {
                urls.insert(URL(fileURLWithPath: ConfigStore.realHomePath))
            }
        }
        FIFinderSyncController.default().directoryURLs = urls
    }

    // MARK: - Toolbar Metadata

    override var toolbarItemName: String {
        L10n.appName(config.language)
    }

    override var toolbarItemToolTip: String {
        L10n.appName(config.language)
    }

    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "NanoRight") ?? NSImage()
    }

    // MARK: - Context Menu Generation

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        config = configStore.reloadConfigIfNeeded()
        cutState = configStore.reloadCutStateIfNeeded()
        menuCommandsByTag.removeAll(keepingCapacity: true)
        nextMenuTag = 1

        let controller = FIFinderSyncController.default()
        let targetedURL = controller.targetedURL()
        let selectedURLs = controller.selectedItemURLs() ?? []
        let targetDirPath = targetedURL?.path

        let menu = NSMenu(title: L10n.appName(config.language))
        let lang = config.language

        switch menuKind {
        case .contextualMenuForContainer, .toolbarItemMenu:
            buildContainerMenu(into: menu, targetDir: targetDirPath, selectedURLs: selectedURLs, language: lang)
        case .contextualMenuForItems:
            buildItemsMenu(into: menu, targetDir: targetDirPath, selectedURLs: selectedURLs, language: lang)
        default:
            return nil
        }

        return menu.items.isEmpty ? nil : menu
    }

    // MARK: - Blank Space / Container Menu

    private func buildContainerMenu(
        into menu: NSMenu,
        targetDir: String?,
        selectedURLs: [URL],
        language lang: AppLanguage
    ) {
        let effectiveDir = targetDir ?? selectedURLs.first?.deletingLastPathComponent().path

        // 1. New File (submenu + main-menu promoted items)
        addNewFileItems(into: menu, targetDir: effectiveDir, language: lang)

        // 2. Cut Paste / Cancel Cut (if active)
        if !cutState.isEmpty, let dir = effectiveDir {
            let pasteItem = makeItem(
                title: L10n.menuPasteCut(cutState.paths.count, language: lang),
                symbol: "doc.on.clipboard",
                showIcon: config.toolboxShowIcons,
                command: ActionCommand(kind: .pasteCutItems, targetDirectory: dir, selectedPaths: cutState.paths)
            )
            menu.addItem(pasteItem)

            let cancelItem = makeItem(
                title: L10n.menuCancelCut(lang),
                symbol: "xmark.circle",
                showIcon: config.toolboxShowIcons,
                command: ActionCommand(kind: .cancelCut, targetDirectory: dir)
            )
            menu.addItem(cancelItem)
        }

        // 3. Open in App launchers
        addAppLauncherItems(into: menu, targetDir: effectiveDir, selectedPaths: [], language: lang)

        // 4. Common Folders
        addCommonFoldersItem(into: menu, language: lang)

        // 5. Container-applicable Toolbox actions
        let containerKinds: Set<ToolboxActionKind> = [
            .copyPath, .addToCommonFolders, .toggleHiddenFiles, .lockScreen
        ]
        let applicable = config.toolboxActions.filter { $0.isEnabled && containerKinds.contains($0.kind) }
        addToolboxItems(
            applicable,
            into: menu,
            targetDir: effectiveDir,
            selectedPaths: effectiveDir.map { [$0] } ?? [],
            language: lang
        )
    }

    // MARK: - Selected Items Menu

    private func buildItemsMenu(
        into menu: NSMenu,
        targetDir: String?,
        selectedURLs: [URL],
        language lang: AppLanguage
    ) {
        let paths = selectedURLs.map(\.path)
        let effectiveDir = targetDir ?? selectedURLs.first?.deletingLastPathComponent().path

        let hasDirectories = selectedURLs.contains { isDirectory($0) }
        let hasFiles = selectedURLs.contains { !isDirectory($0) }
        let isSingleImage = selectedURLs.count == 1 && isImageFile(selectedURLs[0])

        // 1. Send To (Move / Copy)
        addSendToItems(into: menu, selectedPaths: paths, language: lang)

        // 2. Open in App launchers
        addAppLauncherItems(into: menu, targetDir: effectiveDir, selectedPaths: paths, language: lang)

        // 3. Common Folders
        addCommonFoldersItem(into: menu, language: lang)

        // 4. Item-applicable Toolbox actions
        let applicable = config.toolboxActions.filter { item in
            guard item.isEnabled else { return false }
            switch item.kind {
            case .dissolveFolder:
                return hasDirectories
            case .newFolderFromFile:
                return hasFiles
            case .setWallpaper:
                return isSingleImage
            case .addToCommonFolders:
                return hasDirectories
            case .lockScreen:
                return false
            default:
                return true
            }
        }
        addToolboxItems(
            applicable,
            into: menu,
            targetDir: effectiveDir,
            selectedPaths: paths,
            language: lang
        )
    }

    // MARK: - Section Builders

    private func addNewFileItems(into menu: NSMenu, targetDir: String?, language lang: AppLanguage) {
        guard let dir = targetDir else { return }
        let enabled = config.newFileTemplates.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }

        // Promoted top-level items
        for template in enabled where template.showInMainMenu {
            let cmd = template.isCustomPrompt
                ? ActionCommand(kind: .customNewFile, targetDirectory: dir)
                : ActionCommand(kind: .newFile(templateId: template.id), targetDirectory: dir)
            let item = makeItem(
                title: template.name,
                symbol: template.sfSymbol,
                showIcon: config.newFileShowIcons,
                command: cmd
            )
            menu.addItem(item)
        }

        // Submenu with all enabled templates
        let submenu = NSMenu(title: L10n.menuNewFile(lang))
        for template in enabled {
            let cmd = template.isCustomPrompt
                ? ActionCommand(kind: .customNewFile, targetDirectory: dir)
                : ActionCommand(kind: .newFile(templateId: template.id), targetDirectory: dir)
            let item = makeItem(
                title: template.name,
                symbol: template.sfSymbol,
                showIcon: config.newFileShowIcons,
                command: cmd
            )
            submenu.addItem(item)
        }

        let parent = NSMenuItem(title: L10n.menuNewFile(lang), action: nil, keyEquivalent: "")
        if config.newFileShowIcons {
            parent.image = symbolImage("doc.badge.plus")
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addSendToItems(into menu: NSMenu, selectedPaths: [String], language lang: AppLanguage) {
        guard !selectedPaths.isEmpty, !config.sendToFolders.isEmpty else { return }

        if config.enableMoveTo {
            let moveSubmenu = NSMenu(title: L10n.menuMoveTo(lang))
            for folder in config.sendToFolders {
                let resolved = folder.resolvedURL().path
                let item = makeItem(
                    title: folder.name,
                    symbol: "folder",
                    cachedIconKey: "folder_\(folder.id.uuidString)",
                    showIcon: config.sendToShowIcons,
                    command: ActionCommand(kind: .moveTo(destination: resolved), selectedPaths: selectedPaths)
                )
                moveSubmenu.addItem(item)
            }
            let moveParent = NSMenuItem(title: L10n.menuMoveTo(lang), action: nil, keyEquivalent: "")
            if config.sendToShowIcons {
                moveParent.image = symbolImage("folder.badge.arrow.forward") ?? symbolImage("arrow.right.doc.on.clipboard")
            }
            moveParent.submenu = moveSubmenu
            menu.addItem(moveParent)
        }

        if config.enableCopyTo {
            let copySubmenu = NSMenu(title: L10n.menuCopyTo(lang))
            for folder in config.sendToFolders {
                let resolved = folder.resolvedURL().path
                let item = makeItem(
                    title: folder.name,
                    symbol: "folder",
                    cachedIconKey: "folder_\(folder.id.uuidString)",
                    showIcon: config.sendToShowIcons,
                    command: ActionCommand(kind: .copyTo(destination: resolved), selectedPaths: selectedPaths)
                )
                copySubmenu.addItem(item)
            }
            let copyParent = NSMenuItem(title: L10n.menuCopyTo(lang), action: nil, keyEquivalent: "")
            if config.sendToShowIcons {
                copyParent.image = symbolImage("doc.on.doc")
            }
            copyParent.submenu = copySubmenu
            menu.addItem(copyParent)
        }
    }

    private func addCommonFoldersItem(into menu: NSMenu, language lang: AppLanguage) {
        guard config.enableCommonFolders, !config.commonFolders.isEmpty else { return }
        let submenu = NSMenu(title: L10n.menuCommonFolders(lang))
        for folder in config.commonFolders {
            let resolved = folder.resolvedURL().path
            let item = makeItem(
                title: folder.name,
                symbol: "folder.fill",
                cachedIconKey: "folder_\(folder.id.uuidString)",
                showIcon: config.commonFoldersShowIcons,
                command: ActionCommand(kind: .openFolder(path: resolved))
            )
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: L10n.menuCommonFolders(lang), action: nil, keyEquivalent: "")
        if config.commonFoldersShowIcons {
            parent.image = symbolImage("heart.fill")
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addAppLauncherItems(
        into menu: NSMenu,
        targetDir: String?,
        selectedPaths: [String],
        language lang: AppLanguage
    ) {
        let enabledApps = config.appLaunchers.filter(\.isEnabled)
        guard !enabledApps.isEmpty else { return }

        let targetContainer: NSMenu
        if config.groupAppLaunchersMenu {
            let sub = NSMenu(title: L10n.menuOpenWithApp(lang))
            let parent = NSMenuItem(title: L10n.menuOpenWithApp(lang), action: nil, keyEquivalent: "")
            if config.toolboxShowIcons {
                parent.image = symbolImage("app.dashed")
            }
            parent.submenu = sub
            menu.addItem(parent)
            targetContainer = sub
        } else {
            targetContainer = menu
        }

        for app in enabledApps {
            let title = config.groupAppLaunchersMenu
                ? app.name
                : L10n.menuOpenIn(app.name, language: lang)
            let item = makeItem(
                title: title,
                symbol: app.isTerminal ? "terminal" : "app",
                cachedIconKey: "app_\(app.id.uuidString)",
                showIcon: config.toolboxShowIcons,
                command: ActionCommand(
                    kind: .openInApp(appPath: app.appPath, isTerminal: app.isTerminal),
                    targetDirectory: targetDir,
                    selectedPaths: selectedPaths
                )
            )
            targetContainer.addItem(item)
        }
    }

    private func addToolboxItems(
        _ actions: [ToolboxActionItem],
        into menu: NSMenu,
        targetDir: String?,
        selectedPaths: [String],
        language lang: AppLanguage
    ) {
        guard !actions.isEmpty else { return }

        let targetContainer: NSMenu
        if config.groupToolboxMenu {
            let sub = NSMenu(title: L10n.menuToolbox(lang))
            let parent = NSMenuItem(title: L10n.menuToolbox(lang), action: nil, keyEquivalent: "")
            if config.toolboxShowIcons {
                parent.image = symbolImage("wrench.and.screwdriver")
            }
            parent.submenu = sub
            menu.addItem(parent)
            targetContainer = sub
        } else {
            targetContainer = menu
        }

        for action in actions {
            let cmd = ActionCommand(
                kind: .toolbox(action.kind),
                targetDirectory: targetDir,
                selectedPaths: selectedPaths,
                deleteNeedsConfirmation: config.deleteConfirmation == .askConfirmation
            )
            let item = makeItem(
                title: action.displayName(language: lang),
                symbol: action.kind.sfSymbol,
                showIcon: config.toolboxShowIcons,
                command: cmd
            )
            targetContainer.addItem(item)
        }
    }

    // MARK: - Menu Item & Icon Helpers

    private func makeItem(
        title: String,
        symbol: String,
        cachedIconKey: String? = nil,
        showIcon: Bool,
        command: ActionCommand
    ) -> NSMenuItem {
        let tag = nextMenuTag
        nextMenuTag += 1
        menuCommandsByTag[tag] = command

        let item = NSMenuItem(title: title, action: #selector(handleMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag
        if showIcon {
            if let key = cachedIconKey, let cached = loadCachedIcon(forKey: key) {
                item.image = cached
            } else {
                item.image = symbolImage(symbol)
            }
        }
        return item
    }

    private func loadCachedIcon(forKey key: String) -> NSImage? {
        if let existing = iconMemoryCache[key] {
            return existing
        }
        let url = configStore.iconFileURL(forKey: key)
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        iconMemoryCache[key] = img
        return img
    }

    private func symbolImage(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let configured = image.withSymbolConfiguration(config) ?? image
        configured.size = NSSize(width: 16, height: 16)
        return configured
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func isImageFile(_ url: URL) -> Bool {
        guard !isDirectory(url) else { return false }
        return Self.imageExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Action Dispatch via Custom URL Scheme

    @objc func handleMenuAction(_ sender: NSMenuItem) {
        guard var command = menuCommandsByTag[sender.tag] else {
            NSLog("NanoRightFinder: missing command for tag %ld", sender.tag)
            return
        }

        // Fill live Finder context if needed
        let controller = FIFinderSyncController.default()
        if command.targetDirectory == nil {
            command.targetDirectory = controller.targetedURL()?.path
        }
        if command.selectedPaths.isEmpty, let liveSelected = controller.selectedItemURLs(), !liveSelected.isEmpty {
            switch command.kind {
            case .newFile, .customNewFile, .openFolder, .pasteCutItems, .cancelCut, .openSettings:
                break
            default:
                command.selectedPaths = liveSelected.map(\.path)
            }
        }

        // Dual-channel dispatch (deduplicated by command UUID in NanoRightApp):
        // 1. Shared queue + Darwin notification for sub-millisecond delivery to running host app
        try? configStore.enqueueCommand(command, notify: true)

        // 2. URL scheme wakeup in case NanoRight.app is not currently running
        guard let actionURL = try? command.toURL() else { return }

        let openConfig = NSWorkspace.OpenConfiguration()
        openConfig.activates = command.requiresForeground
        openConfig.hidesOthers = false

        let hostAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        NSWorkspace.shared.open(actionURL, configuration: openConfig) { _, error in
            if error != nil, hostAppURL.pathExtension == "app" {
                NSWorkspace.shared.open([actionURL], withApplicationAt: hostAppURL, configuration: openConfig, completionHandler: nil)
            }
        }
    }
}
