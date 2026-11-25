import AppKit
import NanoRightCore
import SwiftUI

struct NewFileSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selection: Set<UUID> = []

    private var lang: AppLanguage { appState.config.language }

    private var allEnabled: Bool {
        !appState.config.newFileTemplates.isEmpty && appState.config.newFileTemplates.allSatisfy(\.isEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Column header
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { allEnabled },
                    set: { value in
                        for i in appState.config.newFileTemplates.indices {
                            appState.config.newFileTemplates[i].isEnabled = value
                        }
                        appState.save()
                    }
                ))
                .labelsHidden()
                .frame(width: 24)

                Text(L10n.text("启用", "On", language: lang))
                    .frame(width: 30, alignment: .leading)
                Text(L10n.text("显示名称（可直接编辑 / 拖拽排序）", "Display Name (Editable / Drag to Reorder)", language: lang))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("后缀", "Ext", language: lang))
                    .frame(width: 64, alignment: .leading)
                Text(L10n.text("主菜单", "Top Level", language: lang))
                    .frame(width: 64, alignment: .center)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List(selection: $selection) {
                ForEach($appState.config.newFileTemplates) { $template in
                    HStack(spacing: 12) {
                        Toggle("", isOn: $template.isEnabled)
                            .labelsHidden()
                            .onChange(of: template.isEnabled) { _, _ in appState.save() }
                            .frame(width: 24)

                        Image(systemName: template.sfSymbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        TextField("", text: $template.name)
                            .textFieldStyle(.plain)
                            .onSubmit { appState.save() }
                            .onChange(of: template.name) { _, _ in appState.save() }
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(template.fileExtension.isEmpty ? "—" : ".\(template.fileExtension)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)

                        Toggle("", isOn: $template.showInMainMenu)
                            .labelsHidden()
                            .onChange(of: template.showInMainMenu) { _, _ in appState.save() }
                            .frame(width: 64)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { indices, newOffset in
                    appState.config.newFileTemplates.move(fromOffsets: indices, toOffset: newOffset)
                    appState.save()
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            // Action bar + behavior toggles
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        pickTemplateFile()
                    } label: {
                        Label(L10n.text("添加模板文件", "Add Template File", language: lang), systemImage: "plus")
                    }

                    Button {
                        appState.removeNewFileTemplates(ids: selection)
                        selection.removeAll()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection.isEmpty)

                    Spacer()

                    Button(L10n.text("重置默认", "Reset Defaults", language: lang)) {
                        appState.config.newFileTemplates = AppConfig.defaultNewFileTemplates(language: lang)
                        appState.save()
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    Toggle(
                        L10n.text("显示图标", "Show Icons", language: lang),
                        isOn: Binding(
                            get: { appState.config.newFileShowIcons },
                            set: { appState.config.newFileShowIcons = $0; appState.save() }
                        )
                    )
                    Toggle(
                        L10n.text("开启创建提示音", "Play Sound on Create", language: lang),
                        isOn: Binding(
                            get: { appState.config.newFilePlaySound },
                            set: { appState.config.newFilePlaySound = $0; appState.save() }
                        )
                    )
                    Toggle(
                        L10n.text("新建文件后自动打开", "Open File After Creating", language: lang),
                        isOn: Binding(
                            get: { appState.config.newFileAutoOpen },
                            set: { appState.config.newFileAutoOpen = $0; appState.save() }
                        )
                    )
                    Toggle(
                        L10n.text("新建后自动开始重命名", "Auto-Rename After Creating", language: lang),
                        isOn: Binding(
                            get: { appState.config.newFileAutoRename },
                            set: { appState.config.newFileAutoRename = $0; appState.save() }
                        )
                    )
                }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func pickTemplateFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.addCustomTemplateFile(from: url)
        }
    }
}
