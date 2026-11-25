import AppKit
import Foundation
import NanoRightCore

enum IconCacheService {
    /// Renders crisp 32x32 PNG icons for configured apps and folders into
    /// `~/Library/Application Support/NanoRight/icons/` so the sandboxed FinderSync
    /// extension can display them without needing filesystem access to `/Applications`.
    static func syncIcons(for config: AppConfig, store: ConfigStore) {
        try? store.ensureDirectoriesExist()

        for app in config.appLaunchers {
            let dest = store.iconFileURL(forKey: "app_\(app.id.uuidString)")
            if FileManager.default.fileExists(atPath: app.appPath) {
                let icon = NSWorkspace.shared.icon(forFile: app.appPath)
                writePNG(icon, to: dest)
            }
        }

        let allFolders = config.sendToFolders + config.commonFolders
        for folder in allFolders {
            let dest = store.iconFileURL(forKey: "folder_\(folder.id.uuidString)")
            let url = folder.resolvedURL()
            if FileManager.default.fileExists(atPath: url.path) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                writePNG(icon, to: dest)
            }
        }
    }

    private static func writePNG(_ image: NSImage, to url: URL) {
        let size = NSSize(width: 32, height: 32)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
