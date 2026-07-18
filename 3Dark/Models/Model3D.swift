import Foundation

/// Ein archiviertes Modell = ein Ordner im Archiv.
struct Model3D: Identifiable, Equatable, Hashable {
    let folderURL: URL
    var frontmatter: Frontmatter
    var body: String
    var files: [URL]
    var hasMarkdownFile: Bool

    var id: String { folderURL.path }

    static let previewExtensions = ["stl", "3mf", "obj", "ply", "usdz"]

    var title: String {
        let t = frontmatter.string("title")
        return t.isEmpty ? folderURL.lastPathComponent : t
    }

    var tags: [String] { frontmatter.tags }

    var rating: Int { Int(frontmatter.string("bewertung")) ?? 0 }

    /// Die Datei, die für Vorschau und Thumbnail verwendet wird
    /// (bevorzugt in der Reihenfolge von `previewExtensions`).
    var primary3DFile: URL? {
        for ext in Self.previewExtensions {
            if let file = files.first(where: { $0.pathExtension.lowercased() == ext }) {
                return file
            }
        }
        return nil
    }

    var markdownURL: URL { folderURL.appendingPathComponent("model.md") }
    var thumbnailURL: URL { folderURL.appendingPathComponent(".thumbnail.png") }

    static func isPreviewable(_ url: URL) -> Bool {
        previewExtensions.contains(url.pathExtension.lowercased())
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
