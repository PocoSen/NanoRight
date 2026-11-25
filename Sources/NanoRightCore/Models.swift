import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    public var id: String { rawValue }

    public var isChinese: Bool {
        switch self {
        case .zhHans:
            return true
        case .en:
            return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? true
        }
    }
}

public enum ScopeMode: String, Codable, CaseIterable, Identifiable {
    case allDisks
    case homeDirectory
    case custom

    public var id: String { rawValue }
}

public enum CopyPathStyle: String, Codable, CaseIterable, Identifiable {
    case posix
    case shellEscaped

    public var id: String { rawValue }
}

public enum CutBehavior: String, Codable, CaseIterable, Identifiable {
    case keepVisible
    case markHidden

    public var id: String { rawValue }
}

public enum DeleteConfirmation: String, Codable, CaseIterable, Identifiable {
    case askConfirmation
    case immediate

    public var id: String { rawValue }
}

public struct NewFileTemplate: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var fileExtension: String
    public var isEnabled: Bool
    public var showInMainMenu: Bool
    public var isCustomPrompt: Bool
    public var customTemplateFilename: String?
    public var sfSymbol: String

    public init(
        id: UUID = UUID(),
        name: String,
        fileExtension: String,
        isEnabled: Bool = true,
        showInMainMenu: Bool = false,
        isCustomPrompt: Bool = false,
        customTemplateFilename: String? = nil,
        sfSymbol: String = "doc"
    ) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.isEnabled = isEnabled
        self.showInMainMenu = showInMainMenu
        self.isCustomPrompt = isCustomPrompt
        self.customTemplateFilename = customTemplateFilename
        self.sfSymbol = sfSymbol
    }
}

public struct FolderItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var path: String

    public init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    public func resolvedURL(realHomePath: String = ConfigStore.realHomePath) -> URL {
        if path == "~" {
            return URL(fileURLWithPath: realHomePath)
        }
        if path.hasPrefix("~/") {
            let sub = String(path.dropFirst(2))
            return URL(fileURLWithPath: realHomePath).appendingPathComponent(sub)
        }
        return URL(fileURLWithPath: path)
    }
}

public struct AppLauncherItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var appPath: String
    public var isEnabled: Bool
    public var isTerminal: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        appPath: String,
        isEnabled: Bool = true,
        isTerminal: Bool = false
    ) {
        self.id = id
        self.name = name
        self.appPath = appPath
        self.isEnabled = isEnabled
        self.isTerminal = isTerminal
    }
}

public enum ToolboxActionKind: String, Codable, CaseIterable, Identifiable {
    case copyPath
    case copyName
    case cut
    case permanentDelete
    case toggleHiddenFiles
    case fileInfoAndHash
    case compressZip
    case newFolderFromFile
    case dissolveFolder
    case aliasToDesktop
    case addToCommonFolders
    case grantWritePermission
    case airDrop
    case setWallpaper
    case printFile
    case lockScreen

    public var id: String { rawValue }

    public var sfSymbol: String {
        switch self {
        case .copyPath: return "link"
        case .copyName: return "textformat"
        case .cut: return "scissors"
        case .permanentDelete: return "trash.slash"
        case .toggleHiddenFiles: return "eye"
        case .fileInfoAndHash: return "info.circle"
        case .compressZip: return "archivebox"
        case .newFolderFromFile: return "folder.badge.plus"
        case .dissolveFolder: return "rectangle.expand.vertical"
        case .aliasToDesktop: return "arrowshape.turn.up.right"
        case .addToCommonFolders: return "heart"
        case .grantWritePermission: return "lock.open"
        case .airDrop: return "dot.radiowaves.left.and.right"
        case .setWallpaper: return "photo"
        case .printFile: return "printer"
        case .lockScreen: return "lock"
        }
    }

    public var defaultEnabled: Bool {
        switch self {
        case .copyPath, .copyName, .cut, .permanentDelete, .toggleHiddenFiles,
             .fileInfoAndHash, .compressZip, .newFolderFromFile, .dissolveFolder,
             .addToCommonFolders, .airDrop, .setWallpaper:
            return true
        case .aliasToDesktop, .grantWritePermission, .printFile, .lockScreen:
            return false
        }
    }
}

public struct ToolboxActionItem: Identifiable, Codable, Equatable {
    public var id: String
    public var kind: ToolboxActionKind
    public var customName: String?
    public var isEnabled: Bool

    public init(kind: ToolboxActionKind, customName: String? = nil, isEnabled: Bool? = nil) {
        self.id = kind.rawValue
        self.kind = kind
        self.customName = customName
        self.isEnabled = isEnabled ?? kind.defaultEnabled
    }

    public func displayName(language: AppLanguage) -> String {
        if let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customName
        }
        return L10n.toolboxTitle(kind, language: language)
    }
}

public struct CutClipboardState: Codable, Equatable {
    public var paths: [String]
    public var cutAt: Date
    public var didHideFiles: Bool

    public init(paths: [String] = [], cutAt: Date = Date(), didHideFiles: Bool = false) {
        self.paths = paths
        self.cutAt = cutAt
        self.didHideFiles = didHideFiles
    }

    public var isEmpty: Bool { paths.isEmpty }
}

public struct AppConfig: Codable, Equatable {
    public var schemaVersion: Int

    // General
    public var showMenuBarIcon: Bool
    public var showDockIcon: Bool
    public var launchAtLogin: Bool
    public var language: AppLanguage
    public var scopeMode: ScopeMode
    public var customScopePaths: [String]

    // New File
    public var newFileTemplates: [NewFileTemplate]
    public var newFileShowIcons: Bool
    public var newFilePlaySound: Bool
    public var newFileAutoOpen: Bool
    public var newFileAutoRename: Bool

    // Send To
    public var sendToFolders: [FolderItem]
    public var sendToShowIcons: Bool
    public var enableMoveTo: Bool
    public var enableCopyTo: Bool

    // Common Folders
    public var commonFolders: [FolderItem]
    public var commonFoldersShowIcons: Bool
    public var enableCommonFolders: Bool

    // Toolbox & App Launchers
    public var toolboxActions: [ToolboxActionItem]
    public var appLaunchers: [AppLauncherItem]
    public var toolboxShowIcons: Bool
    public var groupToolboxMenu: Bool
    public var groupAppLaunchersMenu: Bool
    public var copyPathStyle: CopyPathStyle
    public var cutBehavior: CutBehavior
    public var deleteConfirmation: DeleteConfirmation

    public init(
        schemaVersion: Int = 1,
        showMenuBarIcon: Bool = true,
        showDockIcon: Bool = false,
        launchAtLogin: Bool = false,
        language: AppLanguage = .system,
        scopeMode: ScopeMode = .allDisks,
        customScopePaths: [String] = [],
        newFileTemplates: [NewFileTemplate],
        newFileShowIcons: Bool = true,
        newFilePlaySound: Bool = false,
        newFileAutoOpen: Bool = false,
        newFileAutoRename: Bool = false,
        sendToFolders: [FolderItem],
        sendToShowIcons: Bool = true,
        enableMoveTo: Bool = true,
        enableCopyTo: Bool = true,
        commonFolders: [FolderItem],
        commonFoldersShowIcons: Bool = true,
        enableCommonFolders: Bool = true,
        toolboxActions: [ToolboxActionItem],
        appLaunchers: [AppLauncherItem],
        toolboxShowIcons: Bool = true,
        groupToolboxMenu: Bool = false,
        groupAppLaunchersMenu: Bool = false,
        copyPathStyle: CopyPathStyle = .posix,
        cutBehavior: CutBehavior = .keepVisible,
        deleteConfirmation: DeleteConfirmation = .askConfirmation
    ) {
        self.schemaVersion = schemaVersion
        self.showMenuBarIcon = showMenuBarIcon
        self.showDockIcon = showDockIcon
        self.launchAtLogin = launchAtLogin
        self.language = language
        self.scopeMode = scopeMode
        self.customScopePaths = customScopePaths
        self.newFileTemplates = newFileTemplates
        self.newFileShowIcons = newFileShowIcons
        self.newFilePlaySound = newFilePlaySound
        self.newFileAutoOpen = newFileAutoOpen
        self.newFileAutoRename = newFileAutoRename
        self.sendToFolders = sendToFolders
        self.sendToShowIcons = sendToShowIcons
        self.enableMoveTo = enableMoveTo
        self.enableCopyTo = enableCopyTo
        self.commonFolders = commonFolders
        self.commonFoldersShowIcons = commonFoldersShowIcons
        self.enableCommonFolders = enableCommonFolders
        self.toolboxActions = toolboxActions
        self.appLaunchers = appLaunchers
        self.toolboxShowIcons = toolboxShowIcons
        self.groupToolboxMenu = groupToolboxMenu
        self.groupAppLaunchersMenu = groupAppLaunchersMenu
        self.copyPathStyle = copyPathStyle
        self.cutBehavior = cutBehavior
        self.deleteConfirmation = deleteConfirmation
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case showMenuBarIcon
        case showDockIcon
        case launchAtLogin
        case language
        case scopeMode
        case customScopePaths
        case newFileTemplates
        case newFileShowIcons
        case newFilePlaySound
        case newFileAutoOpen
        case newFileAutoRename
        case sendToFolders
        case sendToShowIcons
        case enableMoveTo
        case enableCopyTo
        case commonFolders
        case commonFoldersShowIcons
        case enableCommonFolders
        case toolboxActions
        case appLaunchers
        case toolboxShowIcons
        case groupToolboxMenu
        case groupAppLaunchersMenu
        case copyPathStyle
        case cutBehavior
        case deleteConfirmation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lang = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        self.showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        self.launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.language = lang
        self.scopeMode = try c.decodeIfPresent(ScopeMode.self, forKey: .scopeMode) ?? .allDisks
        self.customScopePaths = try c.decodeIfPresent([String].self, forKey: .customScopePaths) ?? []
        self.newFileTemplates = try c.decodeIfPresent([NewFileTemplate].self, forKey: .newFileTemplates) ?? Self.defaultNewFileTemplates(language: lang)
        self.newFileShowIcons = try c.decodeIfPresent(Bool.self, forKey: .newFileShowIcons) ?? true
        self.newFilePlaySound = try c.decodeIfPresent(Bool.self, forKey: .newFilePlaySound) ?? false
        self.newFileAutoOpen = try c.decodeIfPresent(Bool.self, forKey: .newFileAutoOpen) ?? false
        self.newFileAutoRename = try c.decodeIfPresent(Bool.self, forKey: .newFileAutoRename) ?? false
        self.sendToFolders = try c.decodeIfPresent([FolderItem].self, forKey: .sendToFolders) ?? Self.defaultSendToFolders(language: lang)
        self.sendToShowIcons = try c.decodeIfPresent(Bool.self, forKey: .sendToShowIcons) ?? true
        self.enableMoveTo = try c.decodeIfPresent(Bool.self, forKey: .enableMoveTo) ?? true
        self.enableCopyTo = try c.decodeIfPresent(Bool.self, forKey: .enableCopyTo) ?? true
        self.commonFolders = try c.decodeIfPresent([FolderItem].self, forKey: .commonFolders) ?? Self.defaultCommonFolders(language: lang)
        self.commonFoldersShowIcons = try c.decodeIfPresent(Bool.self, forKey: .commonFoldersShowIcons) ?? true
        self.enableCommonFolders = try c.decodeIfPresent(Bool.self, forKey: .enableCommonFolders) ?? true
        self.toolboxActions = try c.decodeIfPresent([ToolboxActionItem].self, forKey: .toolboxActions) ?? Self.defaultToolboxActions()
        self.appLaunchers = try c.decodeIfPresent([AppLauncherItem].self, forKey: .appLaunchers) ?? Self.detectInstalledAppLaunchers(language: lang)
        self.toolboxShowIcons = try c.decodeIfPresent(Bool.self, forKey: .toolboxShowIcons) ?? true
        self.groupToolboxMenu = try c.decodeIfPresent(Bool.self, forKey: .groupToolboxMenu) ?? false
        self.groupAppLaunchersMenu = try c.decodeIfPresent(Bool.self, forKey: .groupAppLaunchersMenu) ?? false
        self.copyPathStyle = try c.decodeIfPresent(CopyPathStyle.self, forKey: .copyPathStyle) ?? .posix
        self.cutBehavior = try c.decodeIfPresent(CutBehavior.self, forKey: .cutBehavior) ?? .keepVisible
        self.deleteConfirmation = try c.decodeIfPresent(DeleteConfirmation.self, forKey: .deleteConfirmation) ?? .askConfirmation
    }

    public static func defaultNewFileTemplates(language: AppLanguage = .system) -> [NewFileTemplate] {
        let zh = language.isChinese
        return [
            NewFileTemplate(name: zh ? "自定义创建新文件" : "Custom New File...", fileExtension: "", isEnabled: true, showInMainMenu: false, isCustomPrompt: true, sfSymbol: "doc.badge.plus"),
            NewFileTemplate(name: "TXT", fileExtension: "txt", isEnabled: true, sfSymbol: "doc.text"),
            NewFileTemplate(name: "Markdown", fileExtension: "md", isEnabled: true, sfSymbol: "doc.richtext"),
            NewFileTemplate(name: "Word", fileExtension: "docx", isEnabled: true, sfSymbol: "doc.text.fill"),
            NewFileTemplate(name: "Excel", fileExtension: "xlsx", isEnabled: true, sfSymbol: "tablecells"),
            NewFileTemplate(name: "PPT", fileExtension: "pptx", isEnabled: true, sfSymbol: "rectangle.on.rectangle.angled"),
            NewFileTemplate(name: "JSON", fileExtension: "json", isEnabled: true, sfSymbol: "curlybraces"),
            NewFileTemplate(name: "RTF", fileExtension: "rtf", isEnabled: false, sfSymbol: "doc.plaintext"),
            NewFileTemplate(name: "XML", fileExtension: "xml", isEnabled: false, sfSymbol: "chevron.left.forwardslash.chevron.right"),
            NewFileTemplate(name: "YAML", fileExtension: "yaml", isEnabled: false, sfSymbol: "list.bullet.indent"),
            NewFileTemplate(name: "Shell", fileExtension: "sh", isEnabled: false, sfSymbol: "terminal"),
            NewFileTemplate(name: "Python", fileExtension: "py", isEnabled: false, sfSymbol: "chevron.left.slash.chevron.right"),
            NewFileTemplate(name: "HTML", fileExtension: "html", isEnabled: false, sfSymbol: "globe"),
            NewFileTemplate(name: "CSV", fileExtension: "csv", isEnabled: false, sfSymbol: "tablecells.badge.ellipsis")
        ]
    }

    public static func defaultSendToFolders(language: AppLanguage = .system) -> [FolderItem] {
        let zh = language.isChinese
        return [
            FolderItem(name: zh ? "下载" : "Downloads", path: "~/Downloads"),
            FolderItem(name: zh ? "桌面" : "Desktop", path: "~/Desktop"),
            FolderItem(name: zh ? "文稿" : "Documents", path: "~/Documents"),
            FolderItem(name: zh ? "图片" : "Pictures", path: "~/Pictures"),
            FolderItem(name: zh ? "影片" : "Movies", path: "~/Movies"),
            FolderItem(name: zh ? "音乐" : "Music", path: "~/Music")
        ]
    }

    public static func defaultCommonFolders(language: AppLanguage = .system) -> [FolderItem] {
        let zh = language.isChinese
        return [
            FolderItem(name: zh ? "桌面" : "Desktop", path: "~/Desktop"),
            FolderItem(name: zh ? "下载" : "Downloads", path: "~/Downloads"),
            FolderItem(name: zh ? "文稿" : "Documents", path: "~/Documents"),
            FolderItem(name: zh ? "图片" : "Pictures", path: "~/Pictures")
        ]
    }

    public static func defaultToolboxActions() -> [ToolboxActionItem] {
        ToolboxActionKind.allCases.map { ToolboxActionItem(kind: $0) }
    }

    public static func detectInstalledAppLaunchers(
        language: AppLanguage = .system,
        fileManager: FileManager = .default
    ) -> [AppLauncherItem] {
        let zh = language.isChinese
        let candidates: [(String, String, Bool)] = [
            (zh ? "终端" : "Terminal", "/System/Applications/Utilities/Terminal.app", true),
            ("iTerm", "/Applications/iTerm.app", true),
            ("Warp", "/Applications/Warp.app", true),
            ("Ghostty", "/Applications/Ghostty.app", true),
            ("WezTerm", "/Applications/WezTerm.app", true),
            ("VS Code", "/Applications/Visual Studio Code.app", false),
            ("Cursor", "/Applications/Cursor.app", false),
            ("Zed", "/Applications/Zed.app", false),
            ("Sublime Text", "/Applications/Sublime Text.app", false),
            ("Xcode", "/Applications/Xcode.app", false)
        ]

        var results: [AppLauncherItem] = []
        for (name, path, isTerminal) in candidates {
            if path == "/System/Applications/Utilities/Terminal.app" || fileManager.fileExists(atPath: path) {
                results.append(AppLauncherItem(name: name, appPath: path, isEnabled: true, isTerminal: isTerminal))
            }
        }
        return results
    }

    public static func defaultConfig(
        language: AppLanguage = .system,
        installedApps: [AppLauncherItem]? = nil
    ) -> AppConfig {
        AppConfig(
            language: language,
            newFileTemplates: defaultNewFileTemplates(language: language),
            sendToFolders: defaultSendToFolders(language: language),
            commonFolders: defaultCommonFolders(language: language),
            toolboxActions: defaultToolboxActions(),
            appLaunchers: installedApps ?? detectInstalledAppLaunchers(language: language)
        )
    }
}
