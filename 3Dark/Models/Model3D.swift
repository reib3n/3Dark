import Foundation

/// An archived model = one folder inside the archive.
struct Model3D: Identifiable, Equatable, Hashable {
    let folderURL: URL
    var frontmatter: Frontmatter
    var body: String
    var files: [URL]
    var hasMarkdownFile: Bool

    var id: String { folderURL.path }

    static let previewExtensions = ["stl", "3mf", "obj", "ply", "usdz"]
    static let imageExtensions = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]

    var title: String {
        let t = frontmatter.string("title")
        return t.isEmpty ? folderURL.lastPathComponent : t
    }

    var tags: [String] { frontmatter.tags }

    /// Collections group models that belong together (e.g. a chess set)
    /// via the `collections` front matter field.
    var collections: [String] { frontmatter.list("collections") }

    var rating: Int { Int(frontmatter.string("rating")) ?? 0 }

    /// The file used for preview and thumbnail rendering
    /// (preferred in the order of `previewExtensions`).
    var primary3DFile: URL? {
        for ext in Self.previewExtensions {
            if let file = files.first(where: { $0.pathExtension.lowercased() == ext }) {
                return file
            }
        }
        return nil
    }

    /// All 3D files of the model (for single-part and combined preview).
    var files3D: [URL] {
        files.filter { Model3D.isPreviewable($0) }
    }

    /// User-chosen preview image (front matter `preview_image`, path
    /// relative to the model folder). Replaces the rendered thumbnail.
    var previewImageFile: URL? {
        let relative = frontmatter.string("preview_image")
        guard !relative.isEmpty else { return nil }
        let url = folderURL.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Path of a file relative to the model folder (for display/grouping).
    func relativePath(of file: URL) -> String {
        file.path.replacingOccurrences(of: folderURL.path + "/", with: "")
    }

    /// AI-suggested value for a canonical field (front matter `ai_<key>`).
    func aiSuggestion(_ key: String) -> String {
        frontmatter.string("ai_" + key)
    }

    /// AI-suggested tags (front matter `ai_tags`).
    var aiTags: [String] { frontmatter.list("ai_tags") }

    var markdownURL: URL { folderURL.appendingPathComponent("model.md") }
    var thumbnailURL: URL { folderURL.appendingPathComponent(".thumbnail.png") }

    static func isPreviewable(_ url: URL) -> Bool {
        previewExtensions.contains(url.pathExtension.lowercased())
    }

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    func matches(search: String) -> Bool {
        let needle = search.lowercased()
        if title.lowercased().contains(needle) { return true }
        if tags.contains(where: { $0.lowercased().contains(needle) }) { return true }
        if body.lowercased().contains(needle) { return true }
        if frontmatter.fields.contains(where: { $0.value.lowercased().contains(needle) }) { return true }
        return false
    }
}
