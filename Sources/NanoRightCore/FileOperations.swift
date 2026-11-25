import Foundation
import CryptoKit
import UniformTypeIdentifiers
import Darwin

public struct FileMetadataAndHashes: Equatable {
    public let url: URL
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let sizeBytes: Int64
    public let itemCount: Int?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let posixPermissions: String
    public let typeDescription: String
    public let md5: String?
    public let sha1: String?
    public let sha256: String?
}

public enum FileOperations {
    // MARK: - Path & Name Formatting

    public static func formatPaths(_ paths: [String], style: CopyPathStyle) -> String {
        switch style {
        case .posix:
            return paths.joined(separator: "\n")
        case .shellEscaped:
            return paths.map { shellEscape($0) }.joined(separator: " ")
        }
    }

    public static func formatNames(_ paths: [String]) -> String {
        paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n")
    }

    public static func shellEscape(_ path: String) -> String {
        let safeSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+:@~"))
        if !path.isEmpty && path.unicodeScalars.allSatisfy({ safeSet.contains($0) }) {
            return path
        }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Collision-Safe Move & Copy

    public static func uniqueDestinationURL(for source: URL, in destinationDir: URL, fileManager: FileManager = .default) -> URL {
        let isDir = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let name = source.lastPathComponent
        if isDir {
            return TemplateGenerator.uniqueFileURL(in: destinationDir, baseName: name, fileExtension: "", fileManager: fileManager)
        } else {
            let ext = source.pathExtension
            let base = source.deletingPathExtension().lastPathComponent
            return TemplateGenerator.uniqueFileURL(in: destinationDir, baseName: base, fileExtension: ext, fileManager: fileManager)
        }
    }

    @discardableResult
    public static func moveItems(_ sources: [URL], to destinationDir: URL, fileManager: FileManager = .default) throws -> [URL] {
        var moved: [URL] = []
        let resolvedDestDir = destinationDir.standardizedFileURL

        for src in sources {
            let resolvedSrc = src.standardizedFileURL
            guard fileManager.fileExists(atPath: resolvedSrc.path) else { continue }
            if resolvedSrc.deletingLastPathComponent().standardizedFileURL == resolvedDestDir {
                moved.append(resolvedSrc)
                continue
            }
            let target = uniqueDestinationURL(for: resolvedSrc, in: resolvedDestDir, fileManager: fileManager)
            do {
                try fileManager.moveItem(at: resolvedSrc, to: target)
            } catch {
                // Cross-volume fallback: copy then remove
                try fileManager.copyItem(at: resolvedSrc, to: target)
                try fileManager.removeItem(at: resolvedSrc)
            }
            moved.append(target)
        }
        return moved
    }

    @discardableResult
    public static func copyItems(_ sources: [URL], to destinationDir: URL, fileManager: FileManager = .default) throws -> [URL] {
        var copied: [URL] = []
        let resolvedDestDir = destinationDir.standardizedFileURL

        for src in sources {
            let resolvedSrc = src.standardizedFileURL
            guard fileManager.fileExists(atPath: resolvedSrc.path) else { continue }
            let target = uniqueDestinationURL(for: resolvedSrc, in: resolvedDestDir, fileManager: fileManager)
            try fileManager.copyItem(at: resolvedSrc, to: target)
            copied.append(target)
        }
        return copied
    }

    // MARK: - Dissolve Folder

    @discardableResult
    public static func dissolveFolder(
        _ folderURL: URL,
        trashEmptyFolder: Bool = true,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let parentDir = folderURL.deletingLastPathComponent()
        let children = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        let moved = try moveItems(children, to: parentDir, fileManager: fileManager)

        if trashEmptyFolder {
            do {
                try fileManager.trashItem(at: folderURL, resultingItemURL: nil)
            } catch {
                try fileManager.removeItem(at: folderURL)
            }
        } else {
            try fileManager.removeItem(at: folderURL)
        }
        return moved
    }

    // MARK: - New Folder From Selected File(s)

    @discardableResult
    public static func createFolderFromItems(_ items: [URL], fileManager: FileManager = .default) throws -> URL {
        guard let first = items.first else {
            throw NSError(domain: "NanoRight.FileOperations", code: 10, userInfo: [NSLocalizedDescriptionKey: "No items selected"])
        }
        let parentDir = first.deletingLastPathComponent()
        let stem = first.deletingPathExtension().lastPathComponent
        let baseName = stem.isEmpty ? first.lastPathComponent : stem
        let folderURL = TemplateGenerator.uniqueFileURL(in: parentDir, baseName: baseName, fileExtension: "", fileManager: fileManager)

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        _ = try moveItems(items, to: folderURL, fileManager: fileManager)
        return folderURL
    }

    // MARK: - Native Finder Alias on Desktop

    @discardableResult
    public static func createDesktopAlias(
        for items: [URL],
        desktopURL: URL = URL(fileURLWithPath: ConfigStore.realHomePath).appendingPathComponent("Desktop"),
        fileManager: FileManager = .default
    ) throws -> [URL] {
        var created: [URL] = []
        for item in items {
            let aliasName = item.lastPathComponent
            let target = TemplateGenerator.uniqueFileURL(in: desktopURL, baseName: aliasName, fileExtension: "", fileManager: fileManager)
            let bookmark = try item.bookmarkData(
                options: .suitableForBookmarkFile,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            try URL.writeBookmarkData(bookmark, to: target)
            created.append(target)
        }
        return created
    }

    // MARK: - Permissions & Hidden Flags

    public static func grantWritePermission(for items: [URL], fileManager: FileManager = .default) throws {
        for item in items {
            // Clear user immutable flag (chflags nouchg) if present
            var st = stat()
            if stat(item.path, &st) == 0 {
                if (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
                    _ = chflags(item.path, st.st_flags & ~UInt32(UF_IMMUTABLE))
                }
                let newMode = st.st_mode | mode_t(S_IWUSR)
                if chmod(item.path, newMode) != 0 {
                    let code = Int(errno)
                    throw NSError(domain: NSPOSIXErrorDomain, code: code, userInfo: [
                        NSLocalizedDescriptionKey: "chmod failed for \(item.lastPathComponent): \(String(cString: strerror(errno)))"
                    ])
                }
            } else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                    NSLocalizedDescriptionKey: "File not found: \(item.path)"
                ])
            }
        }
    }

    public static func setHiddenFlag(_ hidden: Bool, for items: [URL]) {
        for item in items {
            var st = stat()
            guard stat(item.path, &st) == 0 else { continue }
            let updatedFlags = hidden
                ? (st.st_flags | UInt32(UF_HIDDEN))
                : (st.st_flags & ~UInt32(UF_HIDDEN))
            _ = chflags(item.path, updatedFlags)
        }
    }

    public static func permanentDelete(_ items: [URL], fileManager: FileManager = .default) throws {
        for item in items {
            if fileManager.fileExists(atPath: item.path) {
                // Ensure unlocked before removal if immutable
                var st = stat()
                if stat(item.path, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
                    _ = chflags(item.path, st.st_flags & ~UInt32(UF_IMMUTABLE))
                }
                try fileManager.removeItem(at: item)
            }
        }
    }

    // MARK: - Compress to ZIP

    @discardableResult
    public static func compressToZip(_ items: [URL], fileManager: FileManager = .default) throws -> URL {
        guard let first = items.first else {
            throw NSError(domain: "NanoRight.FileOperations", code: 20, userInfo: [NSLocalizedDescriptionKey: "No items to compress"])
        }
        let parentDir = first.deletingLastPathComponent()
        let baseName: String
        if items.count == 1 {
            let isDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            baseName = isDir ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent
        } else {
            baseName = "Archive"
        }
        let zipURL = TemplateGenerator.uniqueFileURL(in: parentDir, baseName: baseName, fileExtension: "zip", fileManager: fileManager)

        if items.count == 1 {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, zipURL.path]
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw NSError(domain: "NanoRight.FileOperations", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ZIP compression failed"])
            }
            return zipURL
        } else {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            proc.currentDirectoryURL = parentDir
            proc.arguments = ["-r", "-q", zipURL.path] + items.map(\.lastPathComponent)
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw NSError(domain: "NanoRight.FileOperations", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ZIP compression failed"])
            }
            return zipURL
        }
    }

    // MARK: - File Metadata & Streaming Hashes (MD5 / SHA-1 / SHA-256)

    public static func inspectFile(_ url: URL, fileManager: FileManager = .default) throws -> FileMetadataAndHashes {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
        ]
        let values = try url.resourceValues(forKeys: resourceKeys)
        let isDir = values.isDirectory ?? false
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        let permString = formatPOSIXPermissions(mode)
        let utType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? (isDir ? UTType.folder : UTType(filenameExtension: url.pathExtension))
        let typeDesc = utType?.localizedDescription ?? (isDir ? "Folder" : "File")

        let sizeBytes: Int64
        let itemCount: Int?
        var md5Hex: String?
        var sha1Hex: String?
        var sha256Hex: String?

        if isDir {
            var totalSize: Int64 = 0
            var count = 0
            if let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [],
                errorHandler: nil
            ) {
                for case let child as URL in enumerator {
                    count += 1
                    if let rv = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                       rv.isRegularFile == true,
                       let sz = rv.fileSize {
                        totalSize += Int64(sz)
                    }
                    if count >= 50_000 { break }
                }
            }
            sizeBytes = totalSize
            itemCount = count
        } else {
            sizeBytes = Int64(values.fileSize ?? 0)
            itemCount = nil
            let hashes = try computeStreamingHashes(for: url)
            md5Hex = hashes.md5
            sha1Hex = hashes.sha1
            sha256Hex = hashes.sha256
        }

        return FileMetadataAndHashes(
            url: url,
            name: url.lastPathComponent,
            path: url.path,
            isDirectory: isDir,
            sizeBytes: sizeBytes,
            itemCount: itemCount,
            createdAt: values.creationDate,
            modifiedAt: values.contentModificationDate,
            posixPermissions: permString,
            typeDescription: typeDesc,
            md5: md5Hex,
            sha1: sha1Hex,
            sha256: sha256Hex
        )
    }

    public static func computeStreamingHashes(for url: URL) throws -> (md5: String, sha1: String, sha256: String) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var md5 = Insecure.MD5()
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()

        let chunkSize = 1024 * 1024 // 1 MB streaming chunks
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            md5.update(data: chunk)
            sha1.update(data: chunk)
            sha256.update(data: chunk)
        }

        return (
            md5: md5.finalize().map { String(format: "%02x", $0) }.joined(),
            sha1: sha1.finalize().map { String(format: "%02x", $0) }.joined(),
            sha256: sha256.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    public static func formatPOSIXPermissions(_ mode: UInt16) -> String {
        let perms = mode & 0o777
        let chars: [Character] = [
            (perms & 0o400) != 0 ? "r" : "-",
            (perms & 0o200) != 0 ? "w" : "-",
            (perms & 0o100) != 0 ? "x" : "-",
            (perms & 0o040) != 0 ? "r" : "-",
            (perms & 0o020) != 0 ? "w" : "-",
            (perms & 0o010) != 0 ? "x" : "-",
            (perms & 0o004) != 0 ? "r" : "-",
            (perms & 0o002) != 0 ? "w" : "-",
            (perms & 0o001) != 0 ? "x" : "-"
        ]
        return "\(String(chars)) (\(String(format: "%04o", perms)))"
    }
}
