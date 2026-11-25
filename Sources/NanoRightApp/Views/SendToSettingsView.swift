import AppKit
import NanoRightCore
import SwiftUI

struct SendToSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selection: Set<UUID> = []

    private var lang: AppLanguage { appState.config.language }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(L10n.text("目标路径", "Target Path", language: lang))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("显示名称（可编辑 / 拖拽排序）", "Display Name (Editable / Drag)", language: lang))
                    .frame(width: 220, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List(selection: $selection) {
                ForEach($appState.config.sendToFolders) { $folder in
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 20)

                        Text(folder.path)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        TextField("", text: $folder.name)
                            .textFieldStyle(.plain)
                            .onSubmit { appState.save() }
                            .onChange(of: folder.name) { _, _ in appState.save() }
                            .frame(width: 220, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { indices, newOffset in
                    appState.config.sendToFolders.move(fromOffsets: indices, toOffset: newOffset)
                    appState.save()
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        pickFolder()
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        appState.config.sendToFolders.removeAll { selection.contains($0.id) }
                        selection.removeAll()
                        appState.save()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection.isEmpty)

                    Spacer()

                    Button(L10n.text("重置默认", "Reset Defaults", language: lang)) {
                        appState.config.sendToFolders = AppConfig.defaultSendToFolders(language: lang)
                        appState.save()
                    }
                }

                HStack(spacing: 24) {
                    Toggle(
                        L10n.text("显示图标", "Show Icons", language: lang),
                        isOn: Binding(
                            get: { appState.config.sendToShowIcons },
                            set: { appState.config.sendToShowIcons = $0; appState.save() }
                        )
                    )
                    Toggle(
                        L10n.text("启用“移动文件到...”", "Enable Move To...", language: lang),
                        isOn: Binding(
                            get: { appState.config.enableMoveTo },
                            set: { appState.config.enableMoveTo = $0; appState.save() }
                        )
                    )
                    Toggle(
                        L10n.text("启用“复制文件到...”", "Enable Copy To...", language: lang),
                        isOn: Binding(
                            get: { appState.config.enableCopyTo },
                            set: { appState.config.enableCopyTo = $0; appState.save() }
                        )
                    )
                }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                appState.addSendToFolder(url: url)
            }
        }
    }
}
