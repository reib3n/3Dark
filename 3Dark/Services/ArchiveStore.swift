import AppKit
import SwiftUI

/// Zentrale Datenquelle der App.
///
/// Das Dateisystem ist die einzige Wahrheit: Der Store liest die Ordner
/// unterhalb des Archiv-Wurzelordners ein und schreibt ausschließlich
/// `model.md`-Dateien. Externe Änderungen werden per FSEvents erkannt.
@MainActor
final class ArchiveStore: ObservableObject {
    @Published private(set) var models: [Model3D] = []
    @Published private(set) var rootURL: URL?
    @Published var errorMessage: String?

    private var watcher: FolderWatcher?
    private static let defaultsKey = "ArchiveRootPath"

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.defaultsKey) {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                setRoot(url)
            }
        }
    }

    // MARK: - Wurzelordner

    func chooseRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Als Archiv verwenden"
        panel.message = "Wähle den Wurzelordner deines 3D-Archivs."
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: Self.defaultsKey)
            setRoot(url)
        }
    }

    private func setRoot(_ url: URL) {
        rootURL = url
        watcher = FolderWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    // MARK: - Laden

    func reload() {
        guard let rootURL else {
            models = []
            return
        }
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let loaded = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { loadModel(at: $0) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        models = loaded
    }

    private func loadModel(at folder: URL) -> Model3D {
        var frontmatter = Frontmatter()
        var body = ""
        var hasMarkdown = false
        let markdownURL = folder.appendingPathComponent("model.md")
        if let text = try? String(contentsOf: markdownURL, encoding: .utf8) {
            let parsed = Frontmatter.parse(document: text)
            frontmatter = parsed.frontmatter
            body = parsed.body
            hasMarkdown = true
        }

        let files = ((try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { $0.lastPathComponent != "model.md" }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return Model3D(
            folderURL: folder,
            frontmatter: frontmatter,
            body: body,
            files: files,
            hasMarkdownFile: hasMarkdown
        )
    }

    // MARK: - Schreiben

    func save(_ model: Model3D) {
        var m = model
        if m.frontmatter["title"] == nil {
            m.frontmatter.setString("title", m.folderURL.lastPathComponent)
        }
        if m.frontmatter["tags"] == nil {
            m.frontmatter.tags = []
        }
        do {
            try m.frontmatter.serialized(body: m.body)
                .write(to: m.markdownURL, atomically: true, encoding: .utf8)
            m.hasMarkdownFile = true
            if let index = models.firstIndex(where: { $0.id == m.id }) {
                models[index] = m
            }
        } catch {
            errorMessage = "model.md konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func createModel(named name: String) -> Model3D? {
        guard let rootURL else { return nil }
        let clean = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }

        var folder = rootURL.appendingPathComponent(clean, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = rootURL.appendingPathComponent("\(clean) \(counter)", isDirectory: true)
            counter += 1
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            var frontmatter = Frontmatter()
            frontmatter.setString("title", clean)
            frontmatter.tags = []
            let body = "## Beschreibung\n\n\n## Druckhinweise\n"
            try frontmatter.serialized(body: body)
                .write(to: folder.appendingPathComponent("model.md"), atomically: true, encoding: .utf8)
            reload()
            return models.first { $0.folderURL.path == folder.path }
        } catch {
            errorMessage = "Modell konnte nicht angelegt werden: \(error.localizedDescription)"
            return nil
        }
    }

    func importFiles(_ urls: [URL], into model: Model3D) {
        let fileManager = FileManager.default
        for url in urls {
            let target = model.folderURL.appendingPathComponent(url.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            do {
                try fileManager.copyItem(at: url, to: target)
            } catch {
                errorMessage = "\(url.lastPathComponent) konnte nicht kopiert werden: \(error.localizedDescription)"
            }
        }
        reload()
    }

    // MARK: - Tags

    var tagCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for model in models {
            for tag in model.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Externe Programme

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInCura(_ fileURL: URL) {
        let bundleIDs = ["nl.ultimaker.cura", "com.ultimaker.cura", "org.ultimaker.cura"]
        var appURL = bundleIDs
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first

        if appURL == nil {
            appURL = ["/Applications/UltiMaker Cura.app", "/Applications/Ultimaker Cura.app", "/Applications/Cura.app"]
                .map { URL(fileURLWithPath: $0) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }

        guard let appURL else {
            errorMessage = "Cura wurde nicht gefunden. Ist UltiMaker Cura installiert?"
            return
        }
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
