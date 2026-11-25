import AppKit
import NanoRightCore
import SwiftUI

struct AboutView: View {
    @ObservedObject var appState: AppState
    private var lang: AppLanguage { appState.config.language }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: .indigo.opacity(0.25), radius: 12, y: 6)

            VStack(spacing: 6) {
                Text("\(L10n.appName(lang)) (NanoRight)")
                    .font(.title2.bold())
                Text(L10n.text("版本 1.0.0 · Apple Silicon (arm64) 原生构建", "Version 1.0.0 · Apple Silicon (arm64) Native", language: lang))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.text(
                "一款轻量、免费、无账号登录、专注高频效率的 macOS 访达右键增强工具。",
                "A lightweight, account-free macOS Finder context-menu utility focused on high-frequency workflows.",
                language: lang
            ))
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button(L10n.text("打开配置目录", "Open Config Folder", language: lang)) {
                    try? appState.store.ensureDirectoriesExist()
                    NSWorkspace.shared.open(appState.store.baseDirectory)
                }

                Button(L10n.text("恢复全部默认设置", "Reset All Settings", language: lang)) {
                    appState.config = AppConfig.defaultConfig(language: lang)
                    appState.save()
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
