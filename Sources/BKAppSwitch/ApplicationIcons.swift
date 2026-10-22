import AppKit
import UniformTypeIdentifiers

enum ApplicationIcons {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(bundleIdentifier: String, path: String? = nil) -> NSImage {
        let url: URL?
        if let path, FileManager.default.fileExists(atPath: path) {
            url = URL(fileURLWithPath: path)
        } else {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
        let key = "\(bundleIdentifier)|\(url?.path ?? "")" as NSString
        if let image = cache.object(forKey: key) { return image }
        let original = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        let image = (original.copy() as? NSImage) ?? original
        image.size = NSSize(width: 64, height: 64)
        cache.setObject(image, forKey: key)
        return image
    }

    static func clear() { cache.removeAllObjects() }
}
