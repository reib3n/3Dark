import AppKit
import SwiftUI

/// Central data source of the app.
///
/// The file system is the single source of truth: the store reads the
/// folders below the archive root and only ever writes `model.md` files.
/// External changes are picked up via FSEvents plus periodic polling.
@MainActor
final class ArchiveStore: ObservableObject {
    @Published private(set) var models: [Model3D] = []
    @Published private(set) var trashedModels: [Model3D] = []
    @Published private(set) var rootURL: URL?
    @Published var errorMessage: String?
    /// Freshly imported models that duplicate existing ones — the UI
    /// asks whether to keep or discard each of them.
    @Published var pendingImportDuplicates: [ImportDuplicate] = []

    struct ImportDuplicate: Identifiable {
        let imported: Model3D
        let matches: [Model3D]
        var id: String { imported.id }
    }

    /// Folder inside the archive root where deleted models are parked.
    static let trashFolderName = "deleted"

    private var watcher: FolderWatcher?
    private var pollTimer: Timer?
    private var lastFingerprint: Int?
    private var activePollingConfig: (enabled: Bool, interval: TimeInterval)?
    private var defaultsObserver: NSObjectProtocol?
    private static let defaultsKey = "ArchiveRootPath"

    /// Polling is the fallback next to FSEvents (useful on network and
    /// cloud volumes) — user-configurable, can be turned off entirely.
    static let pollingEnabledKey = "PollingEnabled"
    static let pollingIntervalKey = "PollingInterval"
    static let defaultPollInterval = 15

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.defaultsKey) {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                setRoot(url)
            }
        }
        // React to polling settings changes; reconfigure is a no-op
        // unless the effective values actually changed.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconfigurePolling() }
        }
    }

    // MARK: - Archive root

    func chooseRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Use as Archive")
        panel.message = String(localized: "Choose the root folder of your 3D archive.")
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
        activePollingConfig = nil
        reconfigurePolling()
        reload()
    }

    private func reconfigurePolling() {
        guard rootURL != nil else { return }
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Self.pollingEnabledKey) as? Bool ?? true
        let storedInterval = defaults.integer(forKey: Self.pollingIntervalKey)
        let interval = TimeInterval(storedInterval > 0 ? storedInterval : Self.defaultPollInterval)

        if let active = activePollingConfig, active.enabled == enabled, active.interval == interval {
            return
        }
        activePollingConfig = (enabled, interval)
        pollTimer?.invalidate()
        pollTimer = nil
        guard enabled else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    // MARK: - Loading

    /// Full reload regardless of the fingerprint — used after our own
    /// mutations (import, create, trash) so the UI, including the
    /// "recently added" set, is guaranteed fresh.
    func forceReload() {
        lastFingerprint = nil
        reload()
    }

    func reload() {
        guard let rootURL else {
            models = []
            return
        }
        // Cheap pre-check: hash paths + modification dates only. Skips
        // the expensive full re-parse when nothing changed — this is
        // what keeps the 15 s polling nearly free on quiet archives.
        let fingerprint = Self.archiveFingerprint(of: rootURL)
        if fingerprint == lastFingerprint {
            return
        }
        lastFingerprint = fingerprint

        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let loaded = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .filter { $0.lastPathComponent != Self.trashFolderName }
            .map { loadModel(at: $0) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        // Only publish when something actually changed so that polling
        // does not needlessly touch the UI.
        if loaded != models {
            models = loaded
        }

        let trashURL = rootURL.appendingPathComponent(Self.trashFolderName, isDirectory: true)
        let trashContents = (try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let trashed = trashContents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { loadModel(at: $0) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if trashed != trashedModels {
            trashedModels = trashed
        }
    }

    private static func archiveFingerprint(of rootURL: URL) -> Int {
        var hasher = Hasher()
        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                hasher.combine(url.path)
                if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    hasher.combine(modified.timeIntervalSinceReferenceDate)
                }
            }
        }
        return hasher.finalize()
    }

    private func loadModel(at folder: URL) -> Model3D {
        var frontmatter = Frontmatter()
        var body = ""
        var hasMarkdown = false
        let markdownURL = folder.appendingPathComponent("model.md")
        if let text = try? String(contentsOf: markdownURL, encoding: .utf8) {
            let parsed = Frontmatter.parse(document: text)
            frontmatter = parsed.frontmatter
            frontmatter.migrateLegacyKeys()
            body = parsed.body
            hasMarkdown = true
        }

        // Recursive so that assembly subfolders (parts/, photos/, …)
        // are visible.
        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { continue }
                guard url.lastPathComponent != "model.md" else { continue }
                files.append(url)
            }
        }
        let prefix = folder.path + "/"
        files.sort {
            ModelImporter.hierarchyOrder(
                $0.path.replacingOccurrences(of: prefix, with: ""),
                $1.path.replacingOccurrences(of: prefix, with: "")
            )
        }

        return Model3D(
            folderURL: folder,
            frontmatter: frontmatter,
            body: body,
            files: files,
            hasMarkdownFile: hasMarkdown,
            addedFallbackDate: (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        )
    }

    // MARK: - Writing

    func save(_ model: Model3D) {
        var m = model
        if m.frontmatter["title"] == nil {
            m.frontmatter.setString("title", m.folderURL.lastPathComponent)
        }
        if m.frontmatter["tags"] == nil {
            m.frontmatter.tags = []
        }
        // Freeze the recency anchor: once written, `added` never changes,
        // so editing metadata can't push a model back into "recently
        // added". Legacy models get stamped with their folder date here.
        if m.frontmatter["added"] == nil {
            let anchor = model.addedDate ?? Date()
            m.frontmatter.setString("added", Model3D.addedFormatter.string(from: anchor))
        }
        do {
            try m.frontmatter.serialized(body: m.body)
                .write(to: m.markdownURL, atomically: true, encoding: .utf8)
            m.hasMarkdownFile = true
            if let index = models.firstIndex(where: { $0.id == m.id }) {
                models[index] = m
            }
        } catch {
            errorMessage = String(localized: "Could not save model.md: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createModel(named name: String) -> Model3D? {
        guard let rootURL else { return nil }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let folder = ModelImporter.uniqueFolderURL(for: name, in: rootURL)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            var frontmatter = Frontmatter()
            frontmatter.setString("title", folder.lastPathComponent)
            frontmatter.tags = []
            frontmatter.setString("added", Self.todayISO())
            let body = "## Description\n\n\n## Print Notes\n"
            try frontmatter.serialized(body: body)
                .write(to: folder.appendingPathComponent("model.md"), atomically: true, encoding: .utf8)
            forceReload()
            return models.first { $0.folderURL.path == folder.path }
        } catch {
            errorMessage = String(localized: "Could not create model: \(error.localizedDescription)")
            return nil
        }
    }

    /// Imports ZIPs, folders, or single files as one new model each.
    /// Contained text files are folded into the model.md (see ModelImporter).
    @discardableResult
    func importModels(from urls: [URL]) -> [Model3D] {
        guard let rootURL else { return [] }
        var importedPaths: [String] = []
        var notes: [String] = []

        for url in urls {
            guard url.path != rootURL.path, !url.path.hasPrefix(rootURL.path + "/") else {
                notes.append(String(localized: "\(url.lastPathComponent) is already inside the archive."))
                continue
            }
            do {
                let result = try ModelImporter.importModel(from: url, intoArchive: rootURL)
                importedPaths.append(result.folderURL.path)
                if !result.skippedFiles.isEmpty {
                    notes.append(String(localized: "\(result.folderURL.lastPathComponent): skipped (too large or unreadable): \(result.skippedFiles.joined(separator: ", "))"))
                }
            } catch {
                notes.append(String(localized: "Import of \(url.lastPathComponent) failed: \(error.localizedDescription)"))
            }
        }

        forceReload()
        let imported = models.filter { importedPaths.contains($0.id) }

        // Duplicate check on the freshly imported models only — the
        // files are hot in cache here, so this costs little. Findings
        // go to the UI as a keep-or-discard decision.
        let existing = models.filter { !importedPaths.contains($0.id) }
        Task {
            var found: [ImportDuplicate] = []
            for model in imported {
                let matches = await DuplicateFinder.shared.duplicates(of: model, in: existing)
                if !matches.isEmpty {
                    found.append(ImportDuplicate(imported: model, matches: matches))
                }
            }
            await MainActor.run {
                if !notes.isEmpty {
                    self.errorMessage = notes.joined(separator: "\n")
                }
                self.pendingImportDuplicates = found
            }
        }
        return imported
    }

    func importFiles(_ urls: [URL], into model: Model3D) {
        let fileManager = FileManager.default
        for url in urls {
            let target = model.folderURL.appendingPathComponent(url.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            do {
                try fileManager.copyItem(at: url, to: target)
            } catch {
                errorMessage = String(localized: "Could not copy \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        forceReload()
    }

    // MARK: - Batch actions

    /// Adds a tag to several models at once; existing tags are kept.
    func addTag(_ tag: String, to selection: [Model3D]) {
        let clean = tag.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        for model in selection where !model.tags.contains(clean) {
            var m = model
            m.frontmatter.tags = m.tags + [clean]
            save(m)
        }
    }

    /// Adds a collection to several models at once.
    func addCollection(_ collection: String, to selection: [Model3D]) {
        let clean = collection.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        for model in selection where !model.collections.contains(clean) {
            var m = model
            m.frontmatter.setList("collections", m.collections + [clean])
            save(m)
        }
    }

    func moveToTrash(_ selection: [Model3D]) {
        for model in selection {
            moveToTrash(model)
        }
    }

    /// Stores measured dimensions unless the user already set a value.
    func storeDimensions(_ dimensions: ModelDimensions, for model: Model3D) {
        guard model.frontmatter.string("dimensions").isEmpty else { return }
        var m = model
        m.frontmatter.setString("dimensions", dimensions.frontmatterValue)
        save(m)
    }

    // MARK: - AI enrichment

    /// Writes AI suggestions into `ai_*` front matter fields — only where
    /// the canonical field is still empty; existing values are never
    /// touched. Returns whether anything new was stored.
    @discardableResult
    func applyAISuggestions(_ suggestions: AISuggestions, to model: Model3D) -> Bool {
        var m = model
        var foundSuggestions = false
        for (key, value) in suggestions.fields where m.frontmatter.string(key).isEmpty {
            if m.frontmatter.string("ai_" + key) != value {
                m.frontmatter.setString("ai_" + key, value)
                foundSuggestions = true
            }
        }
        let newTags = suggestions.tags.filter { !m.tags.contains($0) }
        if !newTags.isEmpty, Set(newTags) != Set(m.aiTags) {
            m.frontmatter.setList("ai_tags", newTags)
            foundSuggestions = true
        }
        // Title cleanup is the one suggestion allowed next to a filled
        // field — that's its whole point. Accepting stays manual.
        if let title = suggestions.title,
           title.caseInsensitiveCompare(m.title) != .orderedSame,
           m.frontmatter.string("ai_title") != title {
            m.frontmatter.setString("ai_title", title)
            foundSuggestions = true
        }
        // Always record the check — batch runs use this to skip models
        // that have already been looked at, suggestions or not.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        m.frontmatter.setString("ai_updated", formatter.string(from: Date()))
        save(m)
        return foundSuggestions
    }

    /// Undoes a single import: the freshly created copy goes to the
    /// macOS Trash. The original source outside the archive is never
    /// touched, so nothing is lost.
    func discardImport(_ model: Model3D) {
        do {
            do {
                try FileManager.default.trashItem(at: model.folderURL, resultingItemURL: nil)
            } catch {
                try FileManager.default.removeItem(at: model.folderURL)
            }
            pendingImportDuplicates.removeAll { $0.imported.id == model.id }
            forceReload()
        } catch {
            errorMessage = String(localized: "Could not delete model: \(error.localizedDescription)")
        }
    }

    // MARK: - Trash

    /// Moves a model into the `deleted/` folder inside the archive root.
    func moveToTrash(_ model: Model3D) {
        guard let rootURL else { return }
        let trashURL = rootURL.appendingPathComponent(Self.trashFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
            let target = ModelImporter.uniqueFolderURL(for: model.folderURL.lastPathComponent, in: trashURL)
            try FileManager.default.moveItem(at: model.folderURL, to: target)
            forceReload()
        } catch {
            errorMessage = String(localized: "Could not move model: \(error.localizedDescription)")
        }
    }

    /// Moves a trashed model back into the archive root.
    func restore(_ model: Model3D) {
        guard let rootURL else { return }
        do {
            let target = ModelImporter.uniqueFolderURL(for: model.folderURL.lastPathComponent, in: rootURL)
            try FileManager.default.moveItem(at: model.folderURL, to: target)
            forceReload()
        } catch {
            errorMessage = String(localized: "Could not move model: \(error.localizedDescription)")
        }
    }

    /// Removes a trashed model from the archive; the folder goes to the
    /// macOS Trash when possible (extra safety net), otherwise it is
    /// deleted outright (e.g. network volumes without a trash).
    func deletePermanently(_ model: Model3D) {
        do {
            do {
                try FileManager.default.trashItem(at: model.folderURL, resultingItemURL: nil)
            } catch {
                try FileManager.default.removeItem(at: model.folderURL)
            }
            forceReload()
        } catch {
            errorMessage = String(localized: "Could not delete model: \(error.localizedDescription)")
        }
    }

    static func todayISO() -> String {
        Model3D.addedFormatter.string(from: Date())
    }

    /// Clears the "AI already checked" marker from every model so the
    /// next batch run re-examines the whole archive.
    func resetAICheckStatus() {
        for model in models where !model.frontmatter.string("ai_updated").isEmpty {
            var m = model
            m.frontmatter["ai_updated"] = nil
            save(m)
        }
    }

    // MARK: - Tags & collections

    var tagCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for model in models {
            for tag in model.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
    }

    var collectionCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for model in models {
            for collection in model.collections {
                counts[collection, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - External programs

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
            errorMessage = String(localized: "Cura was not found. Is UltiMaker Cura installed?")
            return
        }
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
