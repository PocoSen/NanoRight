import AppKit
import NanoRightCore
import SwiftUI

@main
struct NanoRightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Window lifecycle & menu bar item are managed by AppDelegate so background
        // `nanoright://` actions from FinderSync never steal focus or pop up Settings.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) var appState: AppState!
    private(set) var dispatcher: ActionDispatcher!

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var launchedViaURL = false
    private var processedCommandIDs: Set<UUID> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        appState = AppState()
        dispatcher = ActionDispatcher(appState: appState)
        setupStandardMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettingsNotification),
            name: .nanoRightOpenSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncMenuBarAndDockPolicy),
            name: .nanoRightMenuBarPreferenceChanged,
            object: nil
        )

        syncMenuBarAndDockPolicy()
        registerPendingCommandDarwinObserver()

        // Drain any commands queued by FinderSync right before host launch
        let startupQueued = appState.store.drainPendingCommands()
        if !startupQueued.isEmpty {
            launchedViaURL = true
            for cmd in startupQueued {
                executeOnce(cmd)
            }
        }

        // Register explicit AppleEvent handler for `kAEReopenApplication` (`rapp`) in addition
        // to `applicationShouldHandleReopen`, ensuring Launchpad / Spotlight / Finder clicks
        // always open Settings even when both Dock and Menu Bar icons are hidden.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleReopenAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEReopenApplication)
        )

        // If launched directly by the user (not triggered silently by FinderSync URL),
        // open the settings window automatically.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if !self.launchedViaURL {
                self.openSettingsWindow()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        launchedViaURL = true
        drainIncomingCommands()
        for url in urls {
            guard let command = try? ActionCommand.fromURL(url) else { continue }
            executeOnce(command)
        }
    }

    private func registerPendingCommandDarwinObserver() {
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            darwinCenter,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    delegate.drainIncomingCommands()
                }
            },
            ConfigStore.pendingCommandNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func drainIncomingCommands() {
        let commands = appState.store.drainPendingCommands()
        for cmd in commands {
            executeOnce(cmd)
        }
    }

    private func executeOnce(_ command: ActionCommand) {
        guard !processedCommandIDs.contains(command.id) else { return }
        processedCommandIDs.insert(command.id)
        if processedCommandIDs.count > 200 {
            processedCommandIDs.removeAll()
        }
        dispatcher.handle(command)
    }

    @objc private func handleReopenAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        openSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appState?.refreshExtensionStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu Bar & Dock Activation Policy

    @objc private func syncMenuBarAndDockPolicy() {
        let showMenuBar = appState.config.showMenuBarIcon
        let showDock = appState.config.showDockIcon
        let wasSettingsVisible = settingsWindow?.isVisible == true

        // 1. Status bar (menu bar) icon
        if showMenuBar {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                if let button = item.button {
                    button.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "NanoRight")
                }
                statusItem = item
            }
            rebuildStatusMenu()
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }

        // 2. Dock icon (.regular shows in Dock; .accessory hides from Dock while still
        //    responding to Launchpad / Spotlight / Finder reopen events and showing windows)
        let targetPolicy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
            if wasSettingsVisible, let window = settingsWindow {
                DispatchQueue.main.async {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    private func rebuildStatusMenu() {
        guard let statusItem else { return }
        let lang = appState.config.language
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: L10n.text("打开简约右键设置...", "Open NanoRight Settings...", language: lang),
            action: #selector(handleOpenSettingsNotification),
            keyEquivalent: ","
        )
        openItem.target = self
        menu.addItem(openItem)

        let restartItem = NSMenuItem(
            title: L10n.text("重启访达 (刷新右键菜单)", "Restart Finder", language: lang),
            action: #selector(handleRestartFinder),
            keyEquivalent: ""
        )
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.text("退出简约右键", "Quit NanoRight", language: lang),
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupStandardMainMenu() {
        let mainMenu = NSMenu()

        // App menu (Cmd+W close window, Cmd+Q quit)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit NanoRight", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (enables Cmd+X/C/V/A in TextFields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Settings Window

    @objc private func handleOpenSettingsNotification() {
        openSettingsWindow()
    }

    @objc private func handleRestartFinder() {
        appState.restartFinder()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    func openSettingsWindow() {
        if let existing = settingsWindow {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.title = "\(L10n.appName(appState.config.language)) — NanoRight"
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = MainSettingsView(appState: appState)
        let hosting = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(L10n.appName(appState.config.language)) — NanoRight"
        window.minSize = NSSize(width: 760, height: 500)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }
}
