import Foundation
import PDFKit

enum ImportError: LocalizedError {
    case sourceMissing(String)
    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let name):
            return String(localized: "\(name) was not found.")
        case .unzipFailed(let name):
            return String(localized: "\(name) could not be unpacked.")
        }
    }
}

/// Imports ZIP files, folders, or single files as a new model.
///
/// Flow: the content is copied/unpacked into a new model folder inside
/// the archive, all contained text files are folded into the markdown
/// part of the model.md in hierarchy order, and afterwards removed from
/// the archive copy (no duplicated content). The source stays untouched.
enum ModelImporter {
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "text"]
    /// Larger text files are not inlined (they remain as files).
    static let maxInlineTextBytes = 512 * 1024
    /// Cap for text pulled out of a single PDF for metadata extraction.
    static let maxPDFExtractionChars = 20_000

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
            // Do not leave half-imported folders behind.
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    static func uniqueFolderURL(for name: String, in rootURL: URL) -> URL {
        let clean = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let base = clean.isEmpty ? "Model" : clean
        var folder = rootURL.appendingPathComponent(base, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = rootURL.appendingPathComponent("\(base) \(counter)", isDirectory: true)
            counter += 1
        }
        return folder
    }

    // MARK: - Steps

    private static func unzip(_ zipURL: URL, to target: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", target.path, "-x", "__MACOSX/*", "*/.DS_Store", ".DS_Store"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        // Exit code 1 = warnings; content was extracted anyway.
        guard process.terminationStatus <= 1 else {
            throw ImportError.unzipFailed(zipURL.lastPathComponent)
        }
    }

    /// Lifts ZIPs with exactly one root folder (GitHub, many portals)
    /// up one level.
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

        // If the import already ships a model.md (migration from another
        // archive), use it as the base instead of overwriting it.
        var frontmatter = Frontmatter()
        var bodyParts: [String] = []
        if let existing = try? String(contentsOf: markdownURL, encoding: .utf8) {
            let parsed = Frontmatter.parse(document: existing)
            frontmatter = parsed.frontmatter
            frontmatter.migrateLegacyKeys()
            let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { bodyParts.append(body) }
        }
        // Collect text files in folder-hierarchy order; PDFs are noted
        // separately for metadata extraction (they stay as files).
        var textFiles: [(relative: String, url: URL)] = []
        var pdfFiles: [URL] = []
        if let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { continue }
                let ext = url.pathExtension.lowercased()
                if ext == "pdf" {
                    pdfFiles.append(url)
                    continue
                }
                guard textExtensions.contains(ext) else { continue }
                let relative = url.path.replacingOccurrences(of: folder.path + "/", with: "")
                guard relative != "model.md" else { continue }
                textFiles.append((relative, url))
            }
        }
        textFiles.sort { hierarchyOrder($0.relative, $1.relative) }

        var inlined: [String] = []
        var skipped: [String] = []
        var extractionText = ""
        for (relative, url) in textFiles {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maxInlineTextBytes, let content = readText(url) else {
                skipped.append(relative)
                continue
            }
            if extractionText.count < 200_000 {
                extractionText += content + "\n"
            }
            bodyParts.append("## \(relative)\n\n" + content.trimmingCharacters(in: .whitespacesAndNewlines))
            inlined.append(relative)
        }

        // Bundled PDFs (description documents) feed the metadata
        // extraction too, but are neither inlined nor removed.
        for pdf in pdfFiles.sorted(by: { $0.path < $1.path }) where extractionText.count < 200_000 {
            if let document = PDFDocument(url: pdf), let content = document.string {
                extractionText += String(content.prefix(maxPDFExtractionChars)) + "\n"
            }
        }

        // Stage-1 metadata extraction: fill empty fields from bundled
        // readme/license texts — never overwrite existing values.
        let extracted = MetadataExtractor.extract(from: extractionText)
        if frontmatter["title"] == nil {
            frontmatter.setString("title", extracted.title ?? title)
        }
        if frontmatter["tags"] == nil { frontmatter.tags = [] }
        if frontmatter["source"] == nil, let source = extracted.source {
            frontmatter.setString("source", source)
        }
        if frontmatter["author"] == nil, let author = extracted.author {
            frontmatter.setString("author", author)
        }
        if frontmatter["license"] == nil, let license = extracted.license {
            frontmatter.setString("license", license)
        }

        if bodyParts.isEmpty {
            bodyParts.append("## Description\n\n\n## Print Notes")
        }
        try frontmatter.serialized(body: bodyParts.joined(separator: "\n\n"))
            .write(to: markdownURL, atomically: true, encoding: .utf8)

        // Only after the model.md has been written successfully: remove
        // the inlined text files from the archive copy.
        for relative in inlined {
            try? fileManager.removeItem(at: folder.appendingPathComponent(relative))
        }
        removeEmptySubdirectories(in: folder)

        return ImportResult(folderURL: folder, inlinedFiles: inlined, skippedFiles: skipped)
    }

    /// Hierarchy order: files of a level first (alphabetically), then
    /// the subfolders — README.txt therefore comes before docs/….
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
        // Deepest first so that nested empty folders fall too.
        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            if let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
               contents.filter({ $0 != ".DS_Store" }).isEmpty {
                try? fileManager.removeItem(at: directory)
            }
        }
    }
}
