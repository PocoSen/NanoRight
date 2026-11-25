import AppKit
import NanoRightCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    private var lang: AppLanguage { appState.config.language }

    var body: some View {
        Form {
            if !appState.isInstalledInApplications {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("尚未安装到「应用程序」目录", "Not Installed in /Applications", language: lang))
                                .font(.headline)
                            Text(L10n.text(
                                "点击右侧按钮即可自动安装到 /Applications（启动台可见）并自动注册访达右键扩展。",
                                "Click Install to move NanoRight into /Applications (visible in Launchpad) and register the Finder extension.",
                                language: lang
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.text("一键安装到应用程序", "Install to /Applications", language: lang)) {
                            appState.installToApplicationsAndRelaunch()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(L10n.text("启动与显示", "Launch & Display", language: lang)) {
                Toggle(
                    L10n.text("开机自动启动", "Launch at Login", language: lang),
                    isOn: Binding(
                        get: { appState.config.launchAtLogin },
                        set: { appState.updateLaunchAtLogin($0) }
                    )
                )

                Toggle(
                    L10n.text("显示菜单栏（状态栏）图标", "Show Menu Bar Icon", language: lang),
                    isOn: Binding(
                        get: { appState.config.showMenuBarIcon },
                        set: {
                            appState.config.showMenuBarIcon = $0
                            appState.save()
                        }
                    )
                )

                Toggle(
                    L10n.text("显示程序坞（Dock）图标", "Show Dock Icon", language: lang),
                    isOn: Binding(
                        get: { appState.config.showDockIcon },
                        set: {
                            appState.config.showDockIcon = $0
                            appState.save()
                        }
                    )
                )

                if !appState.config.showMenuBarIcon && !appState.config.showDockIcon {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.indigo)
                        Text(L10n.text(
                            "无感静默模式已开启：应用在后台静默运行，不在程序坞和状态栏占用位置。需要修改配置时，再次点击启动台（Launchpad）或访达中的「简约右键」图标即可打开本窗口。",
                            "Silent Mode Active: Hidden from both Dock and Menu Bar. Click NanoRight in Launchpad or Finder anytime to reopen Settings.",
                            language: lang
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Picker(
                    L10n.text("界面与菜单语言", "Language", language: lang),
                    selection: Binding(
                        get: { appState.config.language },
                        set: {
                            appState.config.language = $0
                            appState.save()
                        }
                    )
                ) {
                    Text(L10n.text("跟随系统", "Follow System", language: lang)).tag(AppLanguage.system)
                    Text("简体中文").tag(AppLanguage.zhHans)
                    Text("English").tag(AppLanguage.en)
                }

                Picker(
                    L10n.text("访达扩展生效范围", "Finder Scope", language: lang),
                    selection: Binding(
                        get: { appState.config.scopeMode },
                        set: {
                            appState.config.scopeMode = $0
                            appState.save()
                        }
                    )
                ) {
                    Text(L10n.text("所有磁盘（含外接硬盘）", "All Disks & External Volumes", language: lang)).tag(ScopeMode.allDisks)
                    Text(L10n.text("仅个人主目录 (~)", "Home Directory Only (~)", language: lang)).tag(ScopeMode.homeDirectory)
                    Text(L10n.text("自定义目录", "Custom Folders", language: lang)).tag(ScopeMode.custom)
                }

                if appState.config.scopeMode == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.config.customScopePaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    appState.config.customScopePaths.removeAll { $0 == path }
                                    appState.save()
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button(L10n.text("添加监控目录...", "Add Folder...", language: lang)) {
                            pickCustomScopeFolder()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(L10n.text("访达扩展与系统权限", "Finder Extension & Permissions", language: lang)) {
                HStack {
                    extensionStatusBadge
                    Spacer()
                    Button(L10n.text("刷新状态", "Refresh", language: lang)) {
                        appState.refreshExtensionStatus()
                    }
                    Button(L10n.text("前往开启扩展", "Open Extension Settings", language: lang)) {
                        appState.openFinderExtensionsSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("重启访达", "Restart Finder", language: lang))
                        Text(L10n.text("如果右键菜单未立即出现，可尝试重启访达刷新。", "Restart Finder if context menu changes do not appear immediately.", language: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("重启访达", "Restart Finder", language: lang)) {
                        appState.restartFinder()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("完全磁盘访问权限（可选）", "Full Disk Access (Optional)", language: lang))
                        Text(L10n.text("仅在操作受保护目录遇到权限提示时授予。", "Only needed when operating on protected directories.", language: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("前往设置", "Open Settings", language: lang)) {
                        appState.openFullDiskAccessSettings()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("自动化权限（可选）", "Automation Permission (Optional)", language: lang))
                        Text(L10n.text("用于“进入终端 / iTerm”和“新建后自动重命名”。", "Used for opening Terminal / iTerm and auto-renaming new files.", language: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("前往设置", "Open Settings", language: lang)) {
                        appState.openAutomationSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshExtensionStatus()
        }
    }

    @ViewBuilder
    private var extensionStatusBadge: some View {
        switch appState.extensionStatus {
        case .enabled:
            Label(L10n.text("访达扩展已启用", "Finder Extension Enabled", language: lang), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .disabled:
            Label(L10n.text("访达扩展未勾选启用", "Finder Extension Disabled", language: lang), systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .notRegistered:
            Label(L10n.text("尚未注册（请将应用放入 /Applications 或运行 install.sh）", "Not Registered (Move to /Applications or run install.sh)", language: lang), systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .unknown:
            Label(L10n.text("扩展状态检测中...", "Checking Extension Status...", language: lang), systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func pickCustomScopeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                let path = appState.abbreviateHomePath(url.path)
                if !appState.config.customScopePaths.contains(path) {
                    appState.config.customScopePaths.append(path)
                }
            }
            appState.save()
        }
    }
}
