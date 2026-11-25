import Foundation

public enum ActionCommandKind: Codable, Equatable {
    case newFile(templateId: UUID)
    case customNewFile
    case moveTo(destination: String)
    case copyTo(destination: String)
    case openFolder(path: String)
    case openInApp(appPath: String, isTerminal: Bool)
    case toolbox(ToolboxActionKind)
    case pasteCutItems
    case cancelCut
    case openSettings
}

public struct ActionCommand: Codable, Equatable {
    public static let urlScheme = "nanoright"
    public static let urlHost = "action"
    public static let inlinePayloadLimit = 12_000

    public var id: UUID
    public var kind: ActionCommandKind
    public var targetDirectory: String?
    public var selectedPaths: [String]
    public var deleteNeedsConfirmation: Bool

    public init(
        id: UUID = UUID(),
        kind: ActionCommandKind,
        targetDirectory: String? = nil,
        selectedPaths: [String] = [],
        deleteNeedsConfirmation: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.targetDirectory = targetDirectory
        self.selectedPaths = selectedPaths
        self.deleteNeedsConfirmation = deleteNeedsConfirmation
    }

    public var requiresForeground: Bool {
        switch kind {
        case .customNewFile, .openSettings:
            return true
        case .toolbox(let tool):
            switch tool {
            case .fileInfoAndHash, .airDrop, .printFile:
                return true
            case .permanentDelete:
                return deleteNeedsConfirmation
            default:
                return false
            }
        default:
            return false
        }
    }

    public func toURL(tempDirectory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let data = try JSONEncoder().encode(self)
        let base64url = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = Self.urlHost

        if base64url.count <= Self.inlinePayloadLimit {
            components.queryItems = [URLQueryItem(name: "data", value: base64url)]
        } else {
            let fileURL = tempDirectory.appendingPathComponent("nanoright-cmd-\(id.uuidString).json")
            try data.write(to: fileURL, options: .atomic)
            components.queryItems = [URLQueryItem(name: "file", value: fileURL.path)]
        }

        guard let url = components.url else {
            throw NSError(domain: "NanoRight.ActionCommand", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build action URL"])
        }
        return url
    }

    public static func fromURL(_ url: URL) throws -> ActionCommand {
        guard url.scheme?.lowercased() == Self.urlScheme,
              url.host?.lowercased() == Self.urlHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw NSError(domain: "NanoRight.ActionCommand", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid NanoRight URL"])
        }

        if let dataParam = queryItems.first(where: { $0.name == "data" })?.value {
            var base64 = dataParam
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let remainder = base64.count % 4
            if remainder > 0 {
                base64 += String(repeating: "=", count: 4 - remainder)
            }
            guard let raw = Data(base64Encoded: base64) else {
                throw NSError(domain: "NanoRight.ActionCommand", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid base64url payload"])
            }
            return try JSONDecoder().decode(ActionCommand.self, from: raw)
        }

        if let filePath = queryItems.first(where: { $0.name == "file" })?.value {
            let fileURL = URL(fileURLWithPath: filePath)
            let raw = try Data(contentsOf: fileURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            return try JSONDecoder().decode(ActionCommand.self, from: raw)
        }

        throw NSError(domain: "NanoRight.ActionCommand", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing action payload"])
    }
}
