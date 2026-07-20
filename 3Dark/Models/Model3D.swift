import Foundation

/// An archived model = one folder inside the archive.
struct Model3D: Identifiable, Equatable, Hashable {
    let folderURL: URL
    var frontmatter: Frontmatter
    var body: String
    var files: [URL]
    var hasMarkdownFile: Bool
    /// Folder creation date — fallback for models without an `added` field.
    var addedFallbackDate: Date?

    var id: String { folderURL.path }

    /// Mesh formats first — they make the better primary preview; STEP
    /// (point-cloud preview) and F3D (embedded image) come last.
    static let previewExtensions = ["stl", "3mf", "obj", "ply", "usdz", "step", "stp", "f3d"]
    static let imageExtensions = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]
    /// Formats Cura can actually open.
    static let sliceableExtensions = ["stl", "3mf", "obj"]

    var title: String {
        let t = frontmatter.string("title")
        return t.isEmpty ? folderURL.lastPathComponent : t
    }

    var tags: [String] { frontmatter.tags }

    /// Collections group models that belong together (e.g. a chess set)
    /// via the `collections` front matter field.
    var collections: [String] { frontmatter.list("collections") }

    var rating: Int { Int(frontmatter.string("rating")) ?? 0 }

    private static let addedFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    /// When the model entered the archive: front matter `added`
    /// (ISO date, written on create/import), else the folder's
    /// creation date.
    var addedDate: Date? {
        let raw = frontmatter.string("added")
        if !raw.isEmpty, let date = Self.addedFormatter.date(from: raw) {
            return date
        }
        return addedFallbackDate
    }

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

    static func isSliceable(_ url: URL) -> Bool {
        sliceableExtensions.contains(url.pathExtension.lowercased())
    }

    /// Which models count as "recently added" — either younger than
    /// `value` days or the newest `value` models, per the setting.
    static func recentIDs(in models: [Model3D], mode: String, value: Int, now: Date = Date()) -> Set<String> {
        if mode == "count" {
            let newest = models
                .filter { $0.addedDate != nil }
                .sorted { $0.addedDate! > $1.addedDate! }
                .prefix(max(0, value))
            return Set(newest.map(\.id))
        }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, value), to: now) else {
            return []
        }
        return Set(models.filter { ($0.addedDate ?? .distantPast) >= cutoff }.map(\.id))
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
