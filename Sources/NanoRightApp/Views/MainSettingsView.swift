import AppKit
import NanoRightCore
import SwiftUI

enum SidebarTab: String, CaseIterable, Identifiable {
    case general
    case newFile
    case sendTo
    case commonFolders
    case toolbox
    case about

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .newFile: return "doc.badge.plus"
        case .sendTo: return "folder.badge.arrow.forward"
        case .commonFolders: return "heart"
        case .toolbox: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .general: return L10n.text("通用设置", "General", language: lang)
        case .newFile: return L10n.text("新建文件", "New File", language: lang)
        case .sendTo: return L10n.text("发送文件到", "Send File To", language: lang)
        case .commonFolders: return L10n.text("常用目录", "Common Folders", language: lang)
        case .toolbox: return L10n.text("工具箱", "Toolbox", language: lang)
        case .about: return L10n.text("关于", "About", language: lang)
        }
    }
}

struct MainSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: SidebarTab = .general

    private var lang: AppLanguage { appState.config.language }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.indigo, Color.cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.appName(lang))
                            .font(.headline)
                        Text("NanoRight · arm64")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

                List(SidebarTab.allCases, selection: $selectedTab) { tab in
                    Label(tab.title(lang), systemImage: tab.symbol)
                        .tag(tab)
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Label(L10n.text("退出简约右键", "Quit NanoRight", language: lang), systemImage: "power")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if let banner = appState.statusBannerMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(banner)
                            .font(.callout)
                            .lineLimit(2)
                        Spacer()
                        Button(L10n.text("关闭", "Dismiss", language: lang)) {
                            appState.statusBannerMessage = nil
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                }

                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView(appState: appState)
                    case .newFile:
                        NewFileSettingsView(appState: appState)
                    case .sendTo:
                        SendToSettingsView(appState: appState)
                    case .commonFolders:
                        CommonFoldersView(appState: appState)
                    case .toolbox:
                        ToolboxSettingsView(appState: appState)
                    case .about:
                        AboutView(appState: appState)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
