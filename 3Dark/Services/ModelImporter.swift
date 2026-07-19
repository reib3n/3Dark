import Foundation

enum ImportError: LocalizedError {
    case sourceMissing(String)
    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let name):
            return "\(name) wurde nicht gefunden."
        case .unzipFailed(let name):
            return "\(name) konnte nicht entpackt werden."
        }
    }
}

/// Importiert ZIP-Dateien, Ordner oder einzelne Dateien als neues Modell.
///
/// Ablauf: Inhalt wird in einen neuen Modellordner im Archiv kopiert bzw.
/// entpackt, alle enthaltenen Textdateien werden in Hierarchie-Reihenfolge
/// in den Markdown-Teil der model.md übernommen und anschließend aus der
/// Archiv-Kopie gelöscht (kein doppelter Inhalt). Die Quelle bleibt
/// unangetastet.
enum ModelImporter {
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "text"]
    /// Größere Textdateien werden nicht inline übernommen (bleiben als Datei).
    static let maxInlineTextBytes = 512 * 1024

    struct ImportResult {
        let folderURL: URL
        let inlinedFiles: [String]
        let skippedFiles: [String]
    }

    static func importModel(from sourceURL: URL, intoArchive rootURL: URL) throws -> ImportResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw ImportError.sourceMissing(sourceURL.lastPathComponent)
        }
        let isZip = !isDirectory.boolValue && sourceURL.pathExtension.lowercased() == "zip"

        let baseName = isDirectory.boolValue
            ? sourceURL.lastPathComponent
            : sourceURL.deletingPathExtension().lastPathComponent
        let folder = uniqueFolderURL(for: baseName, in: rootURL)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)

        do {
            if isZip {
                try unzip(sourceURL, to: folder)
                try flattenSingleSubdirectory(in: folder)
            } else if isDirectory.boolValue {
                let children = try fileManager.contentsOfDirectory(
                    at: sourceURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                for child in children {
                    try fileManager.copyItem(at: child, to: folder.appendingPathComponent(child.lastPathComponent))
                }
            } else {
                try fileManager.copyItem(at: sourceURL, to: folder.appendingPathComponent(sourceURL.lastPathComponent))
            }
            return try buildModelMarkdown(in: folder, title: baseName)
        } catch {
            // Halb importierte Ordner nicht liegen lassen.
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    static func uniqueFolderURL(for name: String, in rootURL: URL) -> URL {
        let clean = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let base = clean.isEmpty ? "Modell" : clean
        var folder = rootURL.appendingPathComponent(base, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = rootURL.appendingPathComponent("\(base) \(counter)", isDirectory: true)
            counter += 1
        }
        return folder
    }

    // MARK: - Schritte

    private static func unzip(_ zipURL: URL, to target: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", target.path, "-x", "__MACOSX/*", "*/.DS_Store", ".DS_Store"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus <= 1 else {
            throw ImportError.unzipFailed(zipURL.lastPathComponent)
        }
    }

    /// ZIPs mit genau einem Wurzelordner (GitHub, viele Portale) eine Ebene anheben.
    private static func flattenSingleSubdirectory(in folder: URL) throws {
        let fileManager = FileManager.default
        for _ in 0..<3 {
            let contents = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            guard contents.count == 1,
                  let only = contents.first,
                  (try? only.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return
            }
            let children = try fileManager.contentsOfDirectory(at: only, includingPropertiesForKeys: nil, options: [])
            for child in children {
                try fileManager.moveItem(at: child, to: folder.appendingPathComponent(child.lastPathComponent))
            }
            try fileManager.removeItem(at: only)
        }
    }

    private static func buildModelMarkdown(in folder: URL, title: String) throws -> ImportResult {
        let fileManager = FileManager.default
        let markdownURL = folder.appendingPathComponent("model.md")

        // Bringt der Import bereits eine model.md mit (Migration aus einem
        // anderen Archiv), wird sie als Basis übernommen statt überschrieben.
        var frontmatter = Frontmatter()
        var bodyParts: [String] = []
        if let existing = try? String(contentsOf: markdownURL, encoding: .utf8) {
            let parsed = Frontmatter.parse(document: existing)
            frontmatter = parsed.frontmatter
            let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { bodyParts.append(body) }
        }
        if frontmatter["title"] == nil { frontmatter.setString("title", title) }
        if frontmatter["tags"] == nil { frontmatter.tags = [] }

        // Textdateien in Ordner-Hierarchie-Reihenfolge einsammeln.
        var textFiles: [(relative: String, url: URL)] = []
        if let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { continue }
                guard textExtensions.contains(url.pathExtension.lowercased()) else { continue }
                let relative = url.path.replacingOccurrences(of: folder.path + "/", with: "")
                guard relative != "model.md" else { continue }
                textFiles.append((relative, url))
            }
        }
        textFiles.sort { hierarchyOrder($0.relative, $1.relative) }

        var inlined: [String] = []
        var skipped: [String] = []
        for (relative, url) in textFiles {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maxInlineTextBytes, let content = readText(url) else {
                skipped.append(relative)
                continue
            }
            bodyParts.append("## \(relative)\n\n" + content.trimmingCharacters(in: .whitespacesAndNewlines))
            inlined.append(relative)
        }

        if bodyParts.isEmpty {
            bodyParts.append("## Beschreibung\n\n\n## Druckhinweise")
        }
        try frontmatter.serialized(body: bodyParts.joined(separator: "\n\n"))
            .write(to: markdownURL, atomically: true, encoding: .utf8)

        // Erst nach erfolgreichem Schreiben der model.md: übernommene
        // Textdateien aus der Archiv-Kopie entfernen.
        for relative in inlined {
            try? fileManager.removeItem(at: folder.appendingPathComponent(relative))
        }
        removeEmptySubdirectories(in: folder)

        return ImportResult(folderURL: folder, inlinedFiles: inlined, skippedFiles: skipped)
    }

    /// Hierarchie-Reihenfolge: pro Ebene erst die Dateien (alphabetisch),
    /// dann die Unterordner — README.txt kommt also vor docs/….
    static func hierarchyOrder(_ a: String, _ b: String) -> Bool {
        let aComponents = a.components(separatedBy: "/")
        let bComponents = b.components(separatedBy: "/")
        for index in 0..<min(aComponents.count, bComponents.count) {
            let aIsFile = index == aComponents.count - 1
            let bIsFile = index == bComponents.count - 1
            if aIsFile != bIsFile, aComponents[index] != bComponents[index] {
                return aIsFile
            }
            if aComponents[index] != bComponents[index] {
                return aComponents[index].localizedStandardCompare(bComponents[index]) == .orderedAscending
            }
        }
        return aComponents.count < bComponents.count
    }

    private static func readText(_ url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }

    private static func removeEmptySubdirectories(in folder: URL) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        var directories: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                directories.append(url)
            }
        }
        // Tiefste zuerst, damit verschachtelte leere Ordner mitfallen.
        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            if let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
               contents.filter({ $0 != ".DS_Store" }).isEmpty {
                try? fileManager.removeItem(at: directory)
            }
        }
    }
}
