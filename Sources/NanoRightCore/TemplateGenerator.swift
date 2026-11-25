import Foundation

public enum TemplateGenerator {
    /// Generates a unique URL in `directory` without overwriting existing files.
    public static func uniqueFileURL(
        in directory: URL,
        baseName: String,
        fileExtension: String,
        fileManager: FileManager = .default
    ) -> URL {
        let cleanBase = sanitizeFilenameComponent(baseName)
        let cleanExt = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        func makeURL(index: Int) -> URL {
            let stem = index == 1 ? cleanBase : "\(cleanBase) \(index)"
            let filename = cleanExt.isEmpty ? stem : "\(stem).\(cleanExt)"
            return directory.appendingPathComponent(filename)
        }

        var index = 1
        var candidate = makeURL(index: index)
        while fileManager.fileExists(atPath: candidate.path) {
            index += 1
            candidate = makeURL(index: index)
        }
        return candidate
    }

    public static func createFile(
        in directory: URL,
        template: NewFileTemplate,
        customFileName: String? = nil,
        templatesDirectory: URL,
        language: AppLanguage = .system,
        fileManager: FileManager = .default
    ) throws -> URL {
        let targetURL: URL
        let resolvedExt: String

        if let customFileName, !customFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = customFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            let ns = trimmed as NSString
            let ext = ns.pathExtension
            let base = ext.isEmpty ? trimmed : ns.deletingPathExtension
            resolvedExt = ext.isEmpty ? template.fileExtension : ext
            targetURL = uniqueFileURL(in: directory, baseName: base, fileExtension: resolvedExt, fileManager: fileManager)
        } else {
            resolvedExt = template.fileExtension
            let base = L10n.untitledBaseName(language)
            targetURL = uniqueFileURL(in: directory, baseName: base, fileExtension: resolvedExt, fileManager: fileManager)
        }

        // Custom user template file takes priority
        if let customFilename = template.customTemplateFilename {
            let sourceURL = templatesDirectory.appendingPathComponent(customFilename)
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
                return targetURL
            }
        }

        let (data, makeExecutable) = builtInContent(
            forExtension: resolvedExt.lowercased(),
            stem: targetURL.deletingPathExtension().lastPathComponent
        )
        try data.write(to: targetURL, options: .atomic)

        if makeExecutable {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetURL.path)
        }
        return targetURL
    }

    private static func sanitizeFilenameComponent(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\\0")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    private static func builtInContent(forExtension ext: String, stem: String) -> (Data, Bool) {
        switch ext {
        case "docx":
            return (makeMinimalDocx(), false)
        case "xlsx":
            return (makeMinimalXlsx(), false)
        case "pptx":
            return (makeMinimalPptx(), false)
        case "rtf":
            let rtf = "{\\rtf1\\ansi\\ansicpg936\\cocoartf2761\n\\cocoatextscaling0\\cocoaplatform0{\\fonttbl}\n{\\colortbl;\\red255\\green255\\blue255;}\n\\pard\\tx560\\tx1120\\tx1680\\pardirnatural\\partightenfactor0\n\n\\f0\\fs24 \\cf0 }\n"
            return (Data(rtf.utf8), false)
        case "xml":
            return (Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n</root>\n".utf8), false)
        case "json":
            return (Data("{\n  \n}\n".utf8), false)
        case "yaml", "yml":
            return (Data("---\n".utf8), false)
        case "md", "markdown":
            return (Data("# \(stem)\n\n".utf8), false)
        case "html", "htm":
            let html = """
            <!DOCTYPE html>
            <html lang="zh-CN">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>\(stem)</title>
            </head>
            <body>

            </body>
            </html>
            """
            return (Data(html.utf8), false)
        case "sh", "zsh", "bash":
            return (Data("#!/usr/bin/env bash\nset -euo pipefail\n\n".utf8), true)
        case "py":
            return (Data("#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\n\n".utf8), true)
        default:
            return (Data(), false)
        }
    }

    // MARK: - Minimal Spec-Compliant OOXML Generators (Store-Only ZIP)

    private static func makeMinimalDocx() -> Data {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p/>
            <w:sectPr/>
          </w:body>
        </w:document>
        """
        return MinimalZipBuilder.build([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rels.utf8)),
            ("word/document.xml", Data(document.utf8))
        ])
    }

    private static func makeMinimalXlsx() -> Data {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Sheet1" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """
        let sheet1 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData/>
        </worksheet>
        """
        return MinimalZipBuilder.build([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rels.utf8)),
            ("xl/workbook.xml", Data(workbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheet1.utf8))
        ])
    }

    private static func makeMinimalPptx() -> Data {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
          <Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
        </Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
        </Relationships>
        """
        let presentation = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:sldIdLst>
            <p:sldId id="256" r:id="rId1"/>
          </p:sldIdLst>
          <p:sldSz cx="12192000" cy="6858000"/>
          <p:notesSz cx="6858000" cy="9144000"/>
        </p:presentation>
        """
        let presRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
        </Relationships>
        """
        let slide1 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld>
            <p:spTree>
              <p:nvGrpSpPr>
                <p:cNvPr id="1" name=""/>
                <p:cNvGrpSpPr/>
                <p:nvPr/>
              </p:nvGrpSpPr>
              <p:grpSpPr/>
            </p:spTree>
          </p:cSld>
        </p:sld>
        """
        return MinimalZipBuilder.build([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rels.utf8)),
            ("ppt/presentation.xml", Data(presentation.utf8)),
            ("ppt/_rels/presentation.xml.rels", Data(presRels.utf8)),
            ("ppt/slides/slide1.xml", Data(slide1.utf8))
        ])
    }
}

/// Pure-Swift Store-only (uncompressed, method 0) ZIP archive writer with IEEE 802.3 CRC-32.
enum MinimalZipBuilder {
    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    static func build(_ entries: [(String, Data)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for (name, content) in entries {
            let nameData = Data(name.utf8)
            let checksum = crc32(content)
            let size = UInt32(content.count)
            let localOffset = UInt32(archive.count)

            // Local file header
            archive.appendLE(UInt32(0x04034B50))
            archive.appendLE(UInt16(20))             // version needed
            archive.appendLE(UInt16(0x0800))         // UTF-8 flag
            archive.appendLE(UInt16(0))              // compression: store
            archive.appendLE(UInt16(0))              // mod time
            archive.appendLE(UInt16(0))              // mod date
            archive.appendLE(checksum)
            archive.appendLE(size)
            archive.appendLE(size)
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))              // extra length
            archive.append(nameData)
            archive.append(content)

            // Central directory entry
            centralDirectory.appendLE(UInt32(0x02014B50))
            centralDirectory.appendLE(UInt16(20))    // version made by
            centralDirectory.appendLE(UInt16(20))    // version needed
            centralDirectory.appendLE(UInt16(0x0800))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(checksum)
            centralDirectory.appendLE(size)
            centralDirectory.appendLE(size)
            centralDirectory.appendLE(UInt16(nameData.count))
            centralDirectory.appendLE(UInt16(0))     // extra
            centralDirectory.appendLE(UInt16(0))     // comment
            centralDirectory.appendLE(UInt16(0))     // disk start
            centralDirectory.appendLE(UInt16(0))     // internal attrs
            centralDirectory.appendLE(UInt32(0))     // external attrs
            centralDirectory.appendLE(localOffset)
            centralDirectory.append(nameData)
        }

        let cdOffset = UInt32(archive.count)
        let cdSize = UInt32(centralDirectory.count)
        archive.append(centralDirectory)

        // End of central directory record
        archive.appendLE(UInt32(0x06054B50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(cdSize)
        archive.appendLE(cdOffset)
        archive.appendLE(UInt16(0))
        return archive
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
