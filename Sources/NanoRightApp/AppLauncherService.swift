import AppKit
import Foundation
import NanoRightCore

enum AppLauncherService {
    private static let knownTerminalBundleNames: Set<String> = [
        "terminal", "iterm", "iterm2", "warp", "ghostty", "wezterm", "alacritty", "kitty", "hyper", "tabby"
    ]

    static func isLikelyTerminal(appPath: String) -> Bool {
        let stem = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent.lowercased()
        return knownTerminalBundleNames.contains { stem.contains($0) }
    }

    static func open(appPath: String, isTerminal: Bool, targetDirectory: String?, selectedPaths: [String]) {
        let appURL = URL(fileURLWithPath: appPath)
        guard FileManager.default.fileExists(atPath: appURL.path) else { return }

        if isTerminal {
            let dirPath = resolveDirectory(targetDirectory: targetDirectory, selectedPaths: selectedPaths)
            openInTerminal(appURL: appURL, directoryPath: dirPath)
        } else {
            var targets: [URL] = selectedPaths.map { URL(fileURLWithPath: $0) }
            if targets.isEmpty, let targetDirectory {
                targets = [URL(fileURLWithPath: targetDirectory)]
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            if targets.isEmpty {
                NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            } else {
                NSWorkspace.shared.open(targets, withApplicationAt: appURL, configuration: config, completionHandler: nil)
            }
        }
    }

    private static func resolveDirectory(targetDirectory: String?, selectedPaths: [String]) -> String {
        if let first = selectedPaths.first {
            let url = URL(fileURLWithPath: first)
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir ? url.path : url.deletingLastPathComponent().path
        }
        return targetDirectory ?? ConfigStore.realHomePath
    }

    private static func openInTerminal(appURL: URL, directoryPath: String) {
        let appName = appURL.deletingPathExtension().lastPathComponent.lowercased()

        if appName == "terminal" {
            let escaped = FileOperations.shellEscape(directoryPath)
            let script = """
            tell application "Terminal"
                activate
                do script "cd \(escaped.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
            end tell
            """
            if !runAppleScript(script) {
                launchViaOpenCommand(appPath: appURL.path, argumentPath: directoryPath)
            }
            return
        }

        if appName.contains("iterm") {
            let escaped = FileOperations.shellEscape(directoryPath)
            let script = """
            tell application "iTerm"
                activate
                create window with default profile command "cd \(escaped.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")) && exec $SHELL"
            end tell
            """
            if !runAppleScript(script) {
                launchViaOpenCommand(appPath: appURL.path, argumentPath: directoryPath)
            }
            return
        }

        // Warp, Ghostty, WezTerm, Alacritty, Kitty, etc. natively accept a directory argument via `open -a`
        launchViaOpenCommand(appPath: appURL.path, argumentPath: directoryPath)
    }

    private static func launchViaOpenCommand(appPath: String, argumentPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", appPath, argumentPath]
        try? proc.run()
    }

    @discardableResult
    static func runAppleScript(_ source: String) -> Bool {
        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&errorDict)
        return errorDict == nil
    }
}
