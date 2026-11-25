import Foundation

public enum L10n {
    public static func appName(_ lang: AppLanguage) -> String {
        lang.isChinese ? "简约右键" : "NanoRight"
    }

    public static func text(_ zh: String, _ en: String, language: AppLanguage) -> String {
        language.isChinese ? zh : en
    }

    public static func toolboxTitle(_ kind: ToolboxActionKind, language: AppLanguage) -> String {
        let zh = language.isChinese
        switch kind {
        case .copyPath: return zh ? "拷贝路径" : "Copy Path"
        case .copyName: return zh ? "拷贝文件(夹)名称" : "Copy Name"
        case .cut: return zh ? "剪切" : "Cut"
        case .permanentDelete: return zh ? "彻底删除" : "Delete Permanently"
        case .toggleHiddenFiles: return zh ? "显示/隐藏隐藏文件" : "Toggle Hidden Files"
        case .fileInfoAndHash: return zh ? "文件信息与哈希" : "File Info & Hash"
        case .compressZip: return zh ? "压缩为 ZIP" : "Compress to ZIP"
        case .newFolderFromFile: return zh ? "用文件名新建文件夹" : "New Folder with File"
        case .dissolveFolder: return zh ? "解散文件夹" : "Dissolve Folder"
        case .aliasToDesktop: return zh ? "发送替身到桌面" : "Create Alias on Desktop"
        case .addToCommonFolders: return zh ? "添加到常用目录" : "Add to Common Folders"
        case .grantWritePermission: return zh ? "授予写入权限" : "Grant Write Permission"
        case .airDrop: return zh ? "隔空投送" : "AirDrop"
        case .setWallpaper: return zh ? "设置为墙纸" : "Set as Wallpaper"
        case .printFile: return zh ? "打印" : "Print"
        case .lockScreen: return zh ? "锁定屏幕" : "Lock Screen"
        }
    }

    public static func menuNewFile(_ lang: AppLanguage) -> String {
        lang.isChinese ? "新建文件" : "New File"
    }

    public static func menuMoveTo(_ lang: AppLanguage) -> String {
        lang.isChinese ? "移动文件到" : "Move to"
    }

    public static func menuCopyTo(_ lang: AppLanguage) -> String {
        lang.isChinese ? "复制文件到" : "Copy to"
    }

    public static func menuCommonFolders(_ lang: AppLanguage) -> String {
        lang.isChinese ? "常用目录" : "Common Folders"
    }

    public static func menuToolbox(_ lang: AppLanguage) -> String {
        lang.isChinese ? "工具箱" : "Toolbox"
    }

    public static func menuOpenWithApp(_ lang: AppLanguage) -> String {
        lang.isChinese ? "进入 App" : "Open In App"
    }

    public static func menuOpenIn(_ appName: String, language: AppLanguage) -> String {
        language.isChinese ? "进入 \(appName)" : "Open in \(appName)"
    }

    public static func menuPasteCut(_ count: Int, language: AppLanguage) -> String {
        language.isChinese ? "粘贴到此 (\(count) 项)" : "Paste Here (\(count) item\(count == 1 ? "" : "s"))"
    }

    public static func menuCancelCut(_ lang: AppLanguage) -> String {
        lang.isChinese ? "取消剪切" : "Cancel Cut"
    }

    public static func untitledBaseName(_ lang: AppLanguage) -> String {
        lang.isChinese ? "未命名" : "Untitled"
    }
}
