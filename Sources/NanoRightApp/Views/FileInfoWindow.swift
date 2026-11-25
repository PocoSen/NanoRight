import AppKit
import NanoRightCore
import SwiftUI

enum FileInfoWindowController {
    @MainActor
    static func makeWindow(url: URL, language: AppLanguage) -> NSWindow {
        let view = FileInfoInspectorView(url: url, language: language)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(L10n.text("文件信息与哈希", "File Info & Hash", language: language)) — \(url.lastPathComponent)"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.level = .floating
        return window
    }
}

private struct FileInfoInspectorView: View {
    let url: URL
    let language: AppLanguage

    @State private var info: FileMetadataAndHashes?
    @State private var errorMessage: String?
    @State private var copiedField: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let info {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: info.path))
                        .resizable()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(info.typeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: info.sizeBytes, countStyle: .file))
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }

                Divider()

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    infoRow(L10n.text("完整路径", "Path", language: language), value: info.path, copyKey: "path")
                    if let count = info.itemCount {
                        infoRow(L10n.text("包含项目", "Items", language: language), value: "\(count)", copyKey: nil)
                    }
                    infoRow(L10n.text("权限", "Permissions", language: language), value: info.posixPermissions, copyKey: "perm")
                    if let created = info.createdAt {
                        infoRow(L10n.text("创建时间", "Created", language: language), value: Self.dateFormatter.string(from: created), copyKey: nil)
                    }
                    if let modified = info.modifiedAt {
                        infoRow(L10n.text("修改时间", "Modified", language: language), value: Self.dateFormatter.string(from: modified), copyKey: nil)
                    }
                }

                if !info.isDirectory {
                    Divider()
                    Text(L10n.text("校验哈希", "Checksums", language: language))
                        .font(.subheadline.bold())

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                        if let md5 = info.md5 {
                            infoRow("MD5", value: md5, copyKey: "md5")
                        }
                        if let sha1 = info.sha1 {
                            infoRow("SHA-1", value: sha1, copyKey: "sha1")
                        }
                        if let sha256 = info.sha256 {
                            infoRow("SHA-256", value: sha256, copyKey: "sha256")
                        }
                    }
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.text("正在读取文件属性与计算哈希...", "Inspecting file & computing hashes...", language: language))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            let targetURL = url
            let result = await Task.detached(priority: .userInitiated) { () -> Result<FileMetadataAndHashes, Error> in
                Result { try FileOperations.inspectFile(targetURL) }
            }.value
            switch result {
            case .success(let metadata):
                self.info = metadata
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String, copyKey: String?) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let copyKey {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(value, forType: .string)
                    copiedField = copyKey
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedField == copyKey { copiedField = nil }
                    }
                } label: {
                    Image(systemName: copiedField == copyKey ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copiedField == copyKey ? .green : .secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
