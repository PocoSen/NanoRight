import AppKit
import NanoRightCore
import SwiftUI
import UniformTypeIdentifiers

struct ToolboxSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedAppIDs: Set<UUID> = []

    private var lang: AppLanguage { appState.config.language }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // Left: Built-in high-frequency toolbox actions
                VStack(spacing: 0) {
                    HStack {
                        Text(L10n.text("高频文件工具（可拖拽排序）", "Toolbox Actions (Drag to Reorder)", language: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.text("全选", "All", language: lang)) {
                            for i in appState.config.toolboxActions.indices {
                                appState.config.toolboxActions[i].isEnabled = true
                            }
                            appState.save()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    List {
                        ForEach($appState.config.toolboxActions) { $action in
                            HStack(spacing: 10) {
                                Toggle("", isOn: $action.isEnabled)
                                    .labelsHidden()
                                    .onChange(of: action.isEnabled) { _, _ in appState.save() }

                                Image(systemName: action.kind.sfSymbol)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)

                                TextField(
                                    L10n.toolboxTitle(action.kind, language: lang),
                                    text: Binding(
                                        get: { action.customName ?? L10n.toolboxTitle(action.kind, language: lang) },
                                        set: {
                                            action.customName = $0
                                            appState.save()
                                        }
                                    )
                                )
                                .textFieldStyle(.plain)

                                Spacer()

                                inlineOptionPicker(for: action.kind)
                            }
                            .padding(.vertical, 2)
                        }
                        .onMove { indices, newOffset in
                            appState.config.toolboxActions.move(fromOffsets: indices, toOffset: newOffset)
                            appState.save()
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
                .frame(minWidth: 360)

                // Right: Open in App launchers
                VStack(spacing: 0) {
                    HStack {
                        Text(L10n.text("进入 App（终端 / 编辑器）", "Open In App (Terminals & IDEs)", language: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    List(selection: $selectedAppIDs) {
                        ForEach($appState.config.appLaunchers) { $app in
                            HStack(spacing: 10) {
                                Toggle("", isOn: $app.isEnabled)
                                    .labelsHidden()
                                    .onChange(of: app.isEnabled) { _, _ in appState.save() }

                                Image(systemName: app.isTerminal ? "terminal" : "app.dashed")
                                    .foregroundStyle(app.isTerminal ? .green : .blue)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("", text: $app.name)
                                        .textFieldStyle(.plain)
                                        .onChange(of: app.name) { _, _ in appState.save() }
                                    Text(app.appPath)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onMove { indices, newOffset in
                            appState.config.appLaunchers.move(fromOffsets: indices, toOffset: newOffset)
                            appState.save()
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))

                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            pickApplication()
                        } label: {
                            Label(L10n.text("添加应用", "Add App", language: lang), systemImage: "plus")
                        }
                        Button {
                            appState.config.appLaunchers.removeAll { selectedAppIDs.contains($0.id) }
                            selectedAppIDs.removeAll()
                            appState.save()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(selectedAppIDs.isEmpty)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
                .frame(minWidth: 230, idealWidth: 260)
            }

            Divider()

            // Bottom menu layout options + reset
            HStack(spacing: 18) {
                Toggle(
                    L10n.text("显示图标", "Show Icons", language: lang),
                    isOn: Binding(
                        get: { appState.config.toolboxShowIcons },
                        set: { appState.config.toolboxShowIcons = $0; appState.save() }
                    )
                )
                Toggle(
                    L10n.text("折叠工具箱菜单", "Group Toolbox", language: lang),
                    isOn: Binding(
                        get: { appState.config.groupToolboxMenu },
                        set: { appState.config.groupToolboxMenu = $0; appState.save() }
                    )
                )
                Toggle(
                    L10n.text("折叠进入 App 菜单", "Group Open-In Apps", language: lang),
                    isOn: Binding(
                        get: { appState.config.groupAppLaunchersMenu },
                        set: { appState.config.groupAppLaunchersMenu = $0; appState.save() }
                    )
                )

                Spacer()

                Button(L10n.text("重置默认", "Reset Defaults", language: lang)) {
                    appState.config.toolboxActions = AppConfig.defaultToolboxActions()
                    appState.config.appLaunchers = AppConfig.detectInstalledAppLaunchers(language: lang)
                    appState.save()
                }
            }
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func inlineOptionPicker(for kind: ToolboxActionKind) -> some View {
        switch kind {
        case .copyPath:
            Picker("", selection: Binding(
                get: { appState.config.copyPathStyle },
                set: { appState.config.copyPathStyle = $0; appState.save() }
            )) {
                Text(L10n.text("POSIX 路径", "POSIX", language: lang)).tag(CopyPathStyle.posix)
                Text(L10n.text("Shell 转义", "Shell Escaped", language: lang)).tag(CopyPathStyle.shellEscaped)
            }
            .labelsHidden()
            .frame(width: 118)

        case .cut:
            Picker("", selection: Binding(
                get: { appState.config.cutBehavior },
                set: { appState.config.cutBehavior = $0; appState.save() }
            )) {
                Text(L10n.text("剪切时不隐藏", "Keep Visible", language: lang)).tag(CutBehavior.keepVisible)
                Text(L10n.text("剪切时标记隐藏", "Mark Hidden", language: lang)).tag(CutBehavior.markHidden)
            }
            .labelsHidden()
            .frame(width: 128)

        case .permanentDelete:
            Picker("", selection: Binding(
                get: { appState.config.deleteConfirmation },
                set: { appState.config.deleteConfirmation = $0; appState.save() }
            )) {
                Text(L10n.text("需要再次确认", "Ask Confirm", language: lang)).tag(DeleteConfirmation.askConfirmation)
                Text(L10n.text("直接删除", "Immediate", language: lang)).tag(DeleteConfirmation.immediate)
            }
            .labelsHidden()
            .frame(width: 118)

        default:
            EmptyView()
        }
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.addAppLauncher(from: url)
        }
    }
}
