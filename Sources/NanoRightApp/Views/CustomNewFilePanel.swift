import AppKit
import NanoRightCore
import SwiftUI

enum CustomNewFilePanelController {
    @MainActor
    static func makeWindow(
        directory: URL,
        language: AppLanguage,
        onComplete: @escaping (String?) -> Void
    ) -> NSWindow {
        let view = CustomNewFilePromptView(directory: directory, language: language, onComplete: onComplete)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 155),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("自定义创建新文件", "Create Custom File", language: language)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.level = .floating
        return window
    }
}

private struct CustomNewFilePromptView: View {
    let directory: URL
    let language: AppLanguage
    let onComplete: (String?) -> Void

    @State private var filename: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("目标目录：\(directory.path)", "Directory: \(directory.path)", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            TextField(
                L10n.text("输入文件名与后缀（如 notes.md、script.py）", "Enter filename with extension (e.g. notes.md)", language: language),
                text: $filename
            )
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit {
                submit()
            }

            HStack {
                Spacer()
                Button(L10n.text("取消", "Cancel", language: language)) {
                    onComplete(nil)
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.text("创建", "Create", language: language)) {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .onAppear {
            isFocused = true
        }
    }

    private func submit() {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onComplete(trimmed)
    }
}
