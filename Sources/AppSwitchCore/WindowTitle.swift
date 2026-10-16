import Foundation

public enum TitleMode: String, CaseIterable {
    case automatic, projectFirst, editorFirst, original

    public var label: String {
        switch self {
        case .automatic: return "自动识别"
        case .projectFirst: return "项目名在前"
        case .editorFirst: return "文件名在前（VS Code 默认）"
        case .original: return "完整原始标题"
        }
    }
}

public struct WindowTitle: Equatable {
    public let project: String
    public let original: String

    public init(_ title: String, mode: TitleMode = .automatic) {
        let original = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.original = original
        guard !original.isEmpty else {
            project = "未命名窗口"
            return
        }
        guard mode != .original else {
            project = original
            return
        }
        // Split only spaced separators; preserve hyphens in names such as backend-api.
        let separators = [" — ", " – ", " - "]
        let appNames = ["Visual Studio Code - Insiders", "Visual Studio Code", "Code - Insiders", "Code"]
        var content = original
        suffix: for app in appNames {
            for separator in separators where content.hasSuffix(separator + app) {
                content.removeLast((separator + app).count)
                break suffix
            }
        }
        let separator = separators.first { content.contains($0) }
        var parts = separator.map { content.components(separatedBy: $0) } ?? [content]
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count > 1 else {
            project = parts.first ?? original
            return
        }
        switch mode {
        case .projectFirst: project = parts[0]
        case .editorFirst: project = parts[1]
        case .automatic:
            // Titles are user-configurable; this is deliberately a best-effort display
            // hint. The complete title is always retained, and mode is user selectable.
            project = Self.looksLikeEditor(parts[1]) && !Self.looksLikeEditor(parts[0])
                ? parts[0] : parts[1]
        case .original: project = original
        }
    }

    private static func looksLikeEditor(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "●•* "))
        let special = ["Dockerfile", "Makefile", "README", "LICENSE", "Settings", "设置", "Welcome", "欢迎"]
        if special.contains(cleaned) || cleaned.hasPrefix("Untitled-") || cleaned.hasPrefix("未命名-") {
            return true
        }
        if cleaned.hasPrefix(".") { return true }
        let ext = (cleaned as NSString).pathExtension.lowercased()
        return ["swift", "ts", "tsx", "js", "jsx", "json", "md", "py", "go", "rs", "html", "css",
                "scss", "yaml", "yml", "toml", "xml", "txt", "sh", "c", "h", "cpp", "java", "kt",
                "vue", "svelte", "rb", "php", "sql", "ipynb", "lock", "env"].contains(ext)
    }
}
