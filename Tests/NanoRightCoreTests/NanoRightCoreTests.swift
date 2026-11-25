import Foundation
import Testing
@testable import NanoRightCore

@Suite("NanoRightCore Tests")
struct NanoRightCoreTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NanoRightTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("ConfigStore round-trip persistence and mtime reload")
    func configStoreRoundTripAndReload() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ConfigStore(baseDirectory: tempDir.appendingPathComponent("config-root", isDirectory: true))
        var cfg = AppConfig.defaultConfig(language: .zhHans)
        cfg.showMenuBarIcon = false
        cfg.showDockIcon = false
        cfg.copyPathStyle = .shellEscaped
        cfg.scopeMode = .homeDirectory

        try store.saveConfig(cfg, notify: false)
        let loaded = store.loadConfig()
        #expect(loaded == cfg)
        #expect(loaded.showMenuBarIcon == false)
        #expect(loaded.showDockIcon == false)

        // Verify backward-compatible decoding when `showDockIcon` is absent in older config JSON
        let legacyJSON = #"{"schemaVersion":1,"showMenuBarIcon":false,"language":"zhHans"}"#
        let decodedLegacy = try JSONDecoder().decode(AppConfig.self, from: Data(legacyJSON.utf8))
        #expect(decodedLegacy.showMenuBarIcon == false)
        #expect(decodedLegacy.showDockIcon == false)

        cfg.groupToolboxMenu = true
        try store.saveConfig(cfg, notify: false)
        let reloaded = store.reloadConfigIfNeeded()
        #expect(reloaded.groupToolboxMenu == true)
    }

    @Test("CutClipboardState persistence and clearing")
    func cutClipboardStatePersistence() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ConfigStore(baseDirectory: tempDir.appendingPathComponent("cut-root", isDirectory: true))
        let state = CutClipboardState(paths: ["/tmp/a.txt", "/tmp/b.txt"], didHideFiles: true)
        try store.saveCutState(state, notify: false)
        let loaded = store.loadCutState()
        #expect(loaded.paths == state.paths)
        #expect(loaded.didHideFiles == true)

        try store.clearCutState(notify: false)
        #expect(store.loadCutState().isEmpty)

        // Verify pending-commands IPC queue round-trip
        let c1 = ActionCommand(kind: .toolbox(.copyPath), selectedPaths: ["/tmp/x.txt"])
        let c2 = ActionCommand(kind: .customNewFile, targetDirectory: "/tmp")
        try store.enqueueCommand(c1, notify: false)
        try store.enqueueCommand(c2, notify: false)
        let drained = store.drainPendingCommands()
        #expect(drained.count == 2)
        #expect(Set(drained.map(\.id)) == Set([c1.id, c2.id]))
        #expect(store.drainPendingCommands().isEmpty)
    }

    @Test("ActionCommand inline URL codec round-trip")
    func actionCommandInlineURLRoundTrip() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cmd = ActionCommand(
            kind: .toolbox(.copyPath),
            targetDirectory: "/Users/test/Desktop",
            selectedPaths: ["/Users/test/Desktop/hello world.txt"],
            deleteNeedsConfirmation: true
        )
        let url = try cmd.toURL(tempDirectory: tempDir)
        #expect(url.scheme == "nanoright")
        #expect(url.host == "action")
        #expect(url.absoluteString.contains("data="))

        let decoded = try ActionCommand.fromURL(url)
        #expect(decoded == cmd)
        #expect(decoded.requiresForeground == false)
    }

    @Test("ActionCommand large payload temp-file fallback")
    func actionCommandLargePayloadFileFallback() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let hugePaths = (0..<400).map { "/Users/test/Desktop/very_long_folder_name_\($0)/document_\($0).txt" }
        let cmd = ActionCommand(kind: .toolbox(.compressZip), selectedPaths: hugePaths)
        let url = try cmd.toURL(tempDirectory: tempDir)
        #expect(url.absoluteString.contains("file="))

        let decoded = try ActionCommand.fromURL(url)
        #expect(decoded == cmd)
    }

    @Test("TemplateGenerator built-in templates, OOXML ZIP integrity, and custom template")
    func templateGeneratorBuiltInAndOOXMLArchives() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workDir = tempDir.appendingPathComponent("templates-out", isDirectory: true)
        let customTemplatesDir = tempDir.appendingPathComponent("user-templates", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: customTemplatesDir, withIntermediateDirectories: true)

        // Collision-safe naming
        let txtTemplate = NewFileTemplate(name: "TXT", fileExtension: "txt")
        let t1 = try TemplateGenerator.createFile(in: workDir, template: txtTemplate, templatesDirectory: customTemplatesDir, language: .en)
        let t2 = try TemplateGenerator.createFile(in: workDir, template: txtTemplate, templatesDirectory: customTemplatesDir, language: .en)
        #expect(t1.lastPathComponent == "Untitled.txt")
        #expect(t2.lastPathComponent == "Untitled 2.txt")

        // Executable shell script
        let shTemplate = NewFileTemplate(name: "Shell", fileExtension: "sh")
        let shURL = try TemplateGenerator.createFile(in: workDir, template: shTemplate, customFileName: "deploy.sh", templatesDirectory: customTemplatesDir)
        let attrs = try FileManager.default.attributesOfItem(atPath: shURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect((perms & 0o111) == 0o111)

        // Valid OOXML archives (.docx, .xlsx, .pptx) verified by /usr/bin/unzip -t
        for ext in ["docx", "xlsx", "pptx"] {
            let tpl = NewFileTemplate(name: ext.uppercased(), fileExtension: ext)
            let fileURL = try TemplateGenerator.createFile(in: workDir, template: tpl, customFileName: "sample.\(ext)", templatesDirectory: customTemplatesDir)
            let data = try Data(contentsOf: fileURL)
            #expect(data.starts(with: [0x50, 0x4B, 0x03, 0x04]))

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-t", "-q", fileURL.path]
            try proc.run()
            proc.waitUntilExit()
            #expect(proc.terminationStatus == 0)
        }

        // Custom user template copy
        let customPayload = Data("CUSTOM-TEMPLATE-CONTENT".utf8)
        let customFilename = "custom-1.myext"
        try customPayload.write(to: customTemplatesDir.appendingPathComponent(customFilename))
        let customTpl = NewFileTemplate(name: "Custom", fileExtension: "myext", customTemplateFilename: customFilename)
        let createdCustom = try TemplateGenerator.createFile(in: workDir, template: customTpl, customFileName: "hello.myext", templatesDirectory: customTemplatesDir)
        #expect(try Data(contentsOf: createdCustom) == customPayload)
    }

    @Test("Path and filename formatting (POSIX and shell-escaped)")
    func formatPathsAndNames() {
        let paths = ["/Users/a/file.txt", "/Users/a/my folder/it's here.md"]
        #expect(
            FileOperations.formatPaths(paths, style: .posix) ==
            "/Users/a/file.txt\n/Users/a/my folder/it's here.md"
        )
        #expect(
            FileOperations.formatPaths(paths, style: .shellEscaped) ==
            "/Users/a/file.txt '/Users/a/my folder/it'\\''s here.md'"
        )
        #expect(
            FileOperations.formatNames(paths) ==
            "file.txt\nit's here.md"
        )
    }

    @Test("FileOperations copy, folder-from-file, dissolve, alias, chmod, zip, move, delete")
    func fileOperationsEndToEnd() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let srcDir = tempDir.appendingPathComponent("src", isDirectory: true)
        let dstDir = tempDir.appendingPathComponent("dst", isDirectory: true)
        let desktopDir = tempDir.appendingPathComponent("desktop", isDirectory: true)
        for d in [srcDir, dstDir, desktopDir] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }

        let fileA = srcDir.appendingPathComponent("alpha.txt")
        try Data("alpha".utf8).write(to: fileA)

        // Copy twice to verify collision-safe rename
        let c1 = try FileOperations.copyItems([fileA], to: dstDir)
        let c2 = try FileOperations.copyItems([fileA], to: dstDir)
        #expect(c1.first?.lastPathComponent == "alpha.txt")
        #expect(c2.first?.lastPathComponent == "alpha 2.txt")

        // Create folder from file
        let folder = try FileOperations.createFolderFromItems([fileA])
        #expect(folder.lastPathComponent == "alpha")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("alpha.txt").path))

        // Dissolve folder
        let dissolved = try FileOperations.dissolveFolder(folder, trashEmptyFolder: false)
        #expect(dissolved.first?.lastPathComponent == "alpha.txt")
        #expect(!FileManager.default.fileExists(atPath: folder.path))

        // Native Finder Alias
        let restoredFileA = srcDir.appendingPathComponent("alpha.txt")
        let aliases = try FileOperations.createDesktopAlias(for: [restoredFileA], desktopURL: desktopDir)
        #expect(aliases.count == 1)
        #expect(FileManager.default.fileExists(atPath: aliases[0].path))

        // Grant write permission on read-only file
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: restoredFileA.path)
        try FileOperations.grantWritePermission(for: [restoredFileA])
        let updatedAttrs = try FileManager.default.attributesOfItem(atPath: restoredFileA.path)
        let updatedMode = (updatedAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect((updatedMode & 0o200) != 0)

        // Compress to ZIP
        let zipURL = try FileOperations.compressToZip([restoredFileA])
        #expect(FileManager.default.fileExists(atPath: zipURL.path))
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-t", "-q", zipURL.path]
        try unzip.run()
        unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)

        // Move & permanent delete
        let moved = try FileOperations.moveItems([restoredFileA], to: dstDir)
        #expect(moved.count == 1)
        try FileOperations.permanentDelete(moved)
        #expect(!FileManager.default.fileExists(atPath: moved[0].path))
    }

    @Test("Streaming MD5, SHA-1, and SHA-256 hash verification")
    func streamingFileHashes() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sample = tempDir.appendingPathComponent("hello.txt")
        try Data("hello world".utf8).write(to: sample)

        let meta = try FileOperations.inspectFile(sample)
        #expect(meta.isDirectory == false)
        #expect(meta.sizeBytes == 11)
        #expect(meta.md5 == "5eb63bbbe01eeed093cb22bb8f5acdc3")
        #expect(meta.sha1 == "2aae6c35c94fcfb415dbe95f408b9ce91ee846ed")
        #expect(meta.sha256 == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }
}
