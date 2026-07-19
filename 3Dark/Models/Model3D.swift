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
    static let imageExtensions = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]

    var title: String {
        let t = frontmatter.string("title")
        return t.isEmpty ? folderURL.lastPathComponent : t
    }

    var tags: [String] { frontmatter.tags }

    /// Sammlungen fassen zusammengehörige Modelle (z. B. ein Schachspiel)
    /// über das Frontmatter-Feld `sammlungen` zusammen.
    var collections: [String] { frontmatter.list("sammlungen") }

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

    /// Alle 3D-Dateien des Modells (für Einzel- und Gesamtvorschau).
    var files3D: [URL] {
        files.filter { Model3D.isPreviewable($0) }
    }

    /// Pfad einer Datei relativ zum Modellordner (für Anzeige/Gruppierung).
    func relativePath(of file: URL) -> String {
        file.path.replacingOccurrences(of: folderURL.path + "/", with: "")
    }

    var markdownURL: URL { folderURL.appendingPathComponent("model.md") }
    var thumbnailURL: URL { folderURL.appendingPathComponent(".thumbnail.png") }

    static func isPreviewable(_ url: URL) -> Bool {
        previewExtensions.contains(url.pathExtension.lowercased())
    }

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Vom Nutzer gewähltes Vorschaubild (Frontmatter `vorschaubild`,
    /// Pfad relativ zum Modellordner). Ersetzt das gerenderte Thumbnail.
    var previewImageFile: URL? {
        let relative = frontmatter.string("vorschaubild")
        guard !relative.isEmpty else { return nil }
        let url = folderURL.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
