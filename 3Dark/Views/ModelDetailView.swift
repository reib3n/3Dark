import SwiftUI
import UniformTypeIdentifiers

struct ModelDetailView: View {
    @EnvironmentObject private var store: ArchiveStore
    @Environment(\.openURL) private var openURL
    let model: Model3D

    @State private var title: String
    @State private var tagList: [String]
    @State private var collectionList: [String]
    @State private var source: String
    @State private var author: String
    @State private var license: String
    @State private var material: String
    @State private var nozzle: String
    @State private var layerHeight: String
    @State private var supports: String
    @State private var printed: String
    @State private var rating: Int
    @State private var bodyText: String
    @State private var showMarkdownPreview = false
    @State private var previewFile: URL?
    @State private var hoverPreviewFile: URL?
    @State private var showingDeleteConfirmation = false
    @State private var isEnriching = false
    @State private var enrichmentMessage: String?
    @State private var printLogEntries: [PrintLogEntry]
    @State private var measured: ModelDimensions?
    @AppStorage("BedX") private var bedX = 220.0
    @AppStorage("BedY") private var bedY = 220.0
    @AppStorage("BedZ") private var bedZ = 250.0

    init(model: Model3D) {
        self.model = model
        let fm = model.frontmatter
        _title = State(initialValue: fm.string("title").isEmpty ? model.folderURL.lastPathComponent : fm.string("title"))
        _tagList = State(initialValue: fm.tags)
        _collectionList = State(initialValue: fm.list("collections"))
        _source = State(initialValue: fm.string("source"))
        _author = State(initialValue: fm.string("author"))
        _license = State(initialValue: fm.string("license"))
        _material = State(initialValue: fm.string("material"))
        _nozzle = State(initialValue: fm.string("nozzle"))
        _layerHeight = State(initialValue: fm.string("layer_height"))
        _supports = State(initialValue: fm.string("supports"))
        _printed = State(initialValue: fm.string("printed"))
        _rating = State(initialValue: Int(fm.string("rating")) ?? 0)
        _bodyText = State(initialValue: model.body)
        _printLogEntries = State(initialValue: PrintLog.parse(body: model.body))
        _measured = State(initialValue: model.dimensions)
    }

    private var appliedModel: Model3D {
        var m = model
        m.frontmatter.setString("title", title)
        m.frontmatter.tags = tagList
        m.frontmatter.setList("collections", collectionList)
        m.frontmatter.setString("source", source)
        m.frontmatter.setString("author", author)
        m.frontmatter.setString("license", license)
        m.frontmatter.setString("material", material)
        m.frontmatter.setString("nozzle", nozzle)
        m.frontmatter.setString("layer_height", layerHeight)
        m.frontmatter.setString("supports", supports)
        m.frontmatter.setString("printed", printed)
        m.frontmatter.setString("rating", rating == 0 ? "" : String(rating))
        m.body = bodyText
        return m
    }

    private var isDirty: Bool {
        appliedModel != model || !model.hasMarkdownFile
    }

    var body: some View {
        VSplitView {
            Model3DPreviewView(files: model.files3D, selectedFile: $previewFile)
                .frame(minHeight: 200, idealHeight: 300)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metadataSection
                    Divider()
                    PrintLogSection(entries: $printLogEntries) {
                        bodyText = PrintLog.write(printLogEntries, into: bodyText)
                        save()
                    }
                    Divider()
                    markdownSection
                    Divider()
                    filesSection
                }
                .padding()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let fileURLs = urls.filter { $0.isFileURL }
            guard !fileURLs.isEmpty else { return false }
            store.importFiles(fileURLs, into: model)
            return true
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.revealInFinder(model.folderURL)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show model folder in Finder")

                Button {
                    if let file = curaFile { store.openInCura(file) }
                } label: {
                    Label("Open in Cura", systemImage: "printer")
                }
                .help("Send the displayed 3D file to Cura")
                .disabled(curaFile == nil)

                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save changes to model.md (⌘S)")
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)

                if isEnriching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        enrich()
                    } label: {
                        Label("Enrich with AI", systemImage: "sparkles")
                    }
                    .help("Fetches the source page and suggests values for missing fields")
                    .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if isTrashed {
                    Button {
                        store.restore(model)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .help("Restore")

                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Permanently", systemImage: "trash.slash")
                    }
                    .help("Delete Permanently")
                } else {
                    Button {
                        store.moveToTrash(model)
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                    .help("Move to Trash")
                }
            }
        }
        .alert(
            "AI Enrichment",
            isPresented: Binding(
                get: { enrichmentMessage != nil },
                set: { if !$0 { enrichmentMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(enrichmentMessage ?? "")
        }
        .alert("Delete Permanently?", isPresented: $showingDeleteConfirmation) {
            Button("Delete Permanently", role: .destructive) {
                store.deletePermanently(model)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(model.title)” will be moved to the macOS Trash.")
        }
        .navigationTitle(title)
        .task(id: model.primary3DFile) {
            // Measure once and cache in the front matter; existing
            // values (including hand-edited ones) are never replaced.
            guard measured == nil, let file = model.primary3DFile else { return }
            let dimensions = await Task.detached(priority: .utility) {
                DimensionsReader.measure(fileURL: file)
            }.value
            if let dimensions {
                measured = dimensions
                store.storeDimensions(dimensions, for: model)
            }
        }
    }

    private var isTrashed: Bool {
        store.trashedModels.contains { $0.id == model.id }
    }

    /// Valid http(s) URL from the source field, if any.
    private var sourceURL: URL? {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// The file the Cura button targets: the displayed file when Cura
    /// can open it, otherwise the first sliceable file of the model.
    private var curaFile: URL? {
        if let previewFile, Model3D.isSliceable(previewFile) { return previewFile }
        return model.files.first(where: Model3D.isSliceable)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            field("Title", text: $title)
            aiRow("title", text: $title, showWhenFilled: true)

            GridRow {
                Text("Tags")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                TokenField(
                    tokens: $tagList,
                    suggestions: store.tagCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                    placeholder: "Add tag…",
                    accent: .blue,
                    icon: "tag",
                    onEdited: save
                )
                .frame(maxWidth: 420, alignment: .leading)
            }
            GridRow {
                Text("Collections")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                TokenField(
                    tokens: $collectionList,
                    suggestions: store.collectionCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                    placeholder: "Add collection…",
                    accent: .purple,
                    icon: "square.stack.3d.up",
                    onEdited: save
                )
                .frame(maxWidth: 420, alignment: .leading)
            }
            aiTagsRow

            GridRow {
                Text("Source")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("", text: $source, prompt: Text(verbatim: "https://…"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button {
                        if let url = sourceURL { openURL(url) }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.borderless)
                    .disabled(sourceURL == nil)
                    .help("Open source page in browser")
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
            field("Author", text: $author)
            aiRow("author", text: $author)
            field("License", text: $license, prompt: "CC BY 4.0")
            aiRow("license", text: $license)

            GridRow {
                Text("")
                Divider()
            }

            field("Material", text: $material, prompt: "PLA")
            aiRow("material", text: $material)
            field("Nozzle", text: $nozzle, prompt: "0.4")
            aiRow("nozzle", text: $nozzle)
            field("Layer height", text: $layerHeight, prompt: "0.2")
            aiRow("layer_height", text: $layerHeight)
            field("Supports", text: $supports, prompt: "yes / no")
            aiRow("supports", text: $supports)
            field("Printed on", text: $printed, prompt: "YYYY-MM-DD")

            if let dimensions = measured {
                GridRow {
                    Text("Dimensions")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(dimensions.displayValue)
                            .monospacedDigit()
                        let bed = ModelDimensions(x: bedX, y: bedY, z: bedZ)
                        if !dimensions.fits(bed: bed) {
                            Label("Larger than the build volume", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if dimensions.needsRotation(bed: bed) {
                            Label("Fits only when rotated", systemImage: "rotate.3d")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GridRow {
                Text("Rating")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                Picker("Rating", selection: $rating) {
                    Text("–").tag(0)
                    ForEach(1...5, id: \.self) { stars in
                        Text(String(repeating: "★", count: stars)).tag(stars)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 320, alignment: .leading)
                .onChange(of: rating) { _, _ in save() }
            }
        }
    }

    private func field(_ label: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey? = nil) -> some View {
        GridRow {
            Text(label)
                .gridColumnAlignment(.trailing)
                .foregroundStyle(.secondary)
            TextField("", text: text, prompt: prompt.map { Text($0) })
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420, alignment: .leading)
                .onSubmit(save)
        }
    }

    /// Writes the current form state to model.md.
    private func save() {
        store.save(appliedModel)
    }

    // MARK: - AI enrichment

    private func enrich() {
        guard AIEnrichmentService.hasAPIKey else {
            enrichmentMessage = String(localized: "No API key set. Add one in Settings.")
            return
        }
        isEnriching = true
        // Save first so the enrichment sees the current form state.
        let current = appliedModel
        store.save(current)
        Task {
            defer { isEnriching = false }
            do {
                let suggestions = try await AIEnrichmentService.shared.enrich(model: current)
                let changed = store.applyAISuggestions(suggestions, to: current)
                if !changed {
                    enrichmentMessage = String(localized: "No new suggestions found.")
                }
            } catch {
                enrichmentMessage = error.localizedDescription
            }
        }
    }

    /// Suggestion row below a field: shown while the canonical field is
    /// empty and an `ai_<key>` value exists. `showWhenFilled` is for the
    /// title, whose suggestion is a cleanup of an existing value.
    @ViewBuilder
    private func aiRow(_ key: String, text: Binding<String>, showWhenFilled: Bool = false) -> some View {
        let suggestion = model.aiSuggestion(key)
        if !suggestion.isEmpty,
           showWhenFilled || text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
            GridRow {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                    .gridColumnAlignment(.trailing)
                HStack(spacing: 10) {
                    Text(suggestion)
                        .foregroundStyle(.secondary)
                        .italic()
                    Button("Accept") {
                        text.wrappedValue = suggestion
                        var m = appliedModel
                        m.frontmatter["ai_" + key] = nil
                        store.save(m)
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    Button("Dismiss") {
                        var m = appliedModel
                        m.frontmatter["ai_" + key] = nil
                        store.save(m)
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
    }

    /// Suggested tags below the tag field, each addable with one click.
    @ViewBuilder
    private var aiTagsRow: some View {
        let remaining = model.aiTags.filter { !tagList.contains($0) }
        if !remaining.isEmpty {
            GridRow {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                    .gridColumnAlignment(.trailing)
                HStack(spacing: 6) {
                    ForEach(remaining, id: \.self) { tag in
                        Button {
                            acceptAITag(tag)
                        } label: {
                            Label(tag, systemImage: "plus")
                                .font(.callout)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.14)))
                                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                        .help("Accept")
                    }
                    Button("Dismiss all") {
                        var m = appliedModel
                        m.frontmatter["ai_tags"] = nil
                        store.save(m)
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
    }

    private func acceptAITag(_ tag: String) {
        tagList.append(tag)
        var m = appliedModel
        let remaining = model.aiTags.filter { $0 != tag && !tagList.contains($0) }
        m.frontmatter.setList("ai_tags", remaining)
        store.save(m)
    }

    // MARK: - Markdown

    private var markdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description & Print Notes")
                    .font(.headline)
                Spacer()
                Picker("View", selection: $showMarkdownPreview) {
                    Text("Edit").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }

            if showMarkdownPreview {
                Text(renderedMarkdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            } else {
                TextEditor(text: $bodyText)
                    .font(.body.monospaced())
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var renderedMarkdown: AttributedString {
        (try? AttributedString(
            markdown: bodyText,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(bodyText)
    }

    // MARK: - Files

    /// Files grouped by subfolder (root folder first).
    private var groupedFiles: [(directory: String, files: [URL])] {
        var groups: [String: [URL]] = [:]
        for file in model.files {
            let directory = (model.relativePath(of: file) as NSString).deletingLastPathComponent
            groups[directory, default: []].append(file)
        }
        return groups
            .sorted { a, b in
                if a.key.isEmpty != b.key.isEmpty { return a.key.isEmpty }
                return a.key.localizedStandardCompare(b.key) == .orderedAscending
            }
            .map { ($0.key, $0.value) }
    }

    private func isActivePreview(_ file: URL) -> Bool {
        if let previewFile { return previewFile == file }
        return model.files3D.count == 1 && model.files3D.first == file
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files")
                .font(.headline)

            if model.files.isEmpty {
                Text("No files yet – just drag STL/3MF files here or into the folder in Finder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedFiles, id: \.directory) { group in
                    if !group.directory.isEmpty {
                        Label(group.directory, systemImage: "folder")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    ForEach(group.files, id: \.self) { file in
                        fileRow(file, indented: !group.directory.isEmpty)
                    }
                }
                Text("Tip: Click a 3D part to show it in the preview; files can be copied here via drag & drop.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func fileRow(_ file: URL, indented: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: file))
                .foregroundStyle(isActivePreview(file) ? Color.accentColor : .secondary)
                .frame(width: 18)
            if Model3D.isPreviewable(file) {
                Button {
                    previewFile = file
                } label: {
                    Text(file.lastPathComponent)
                        .fontWeight(isActivePreview(file) ? .semibold : .regular)
                        .foregroundStyle(isActivePreview(file) ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
                .help("Show in the 3D preview")
            } else {
                Text(file.lastPathComponent)
            }
            Spacer()
            if Model3D.isSliceable(file) {
                Button("Open in Cura") { store.openInCura(file) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
            if Model3D.isImage(file) {
                let isCurrent = model.frontmatter.string("preview_image") == model.relativePath(of: file)
                Button(isCurrent ? "✓ Thumbnail" : "Use as Thumbnail") {
                    var m = appliedModel
                    m.frontmatter.setString("preview_image", isCurrent ? "" : model.relativePath(of: file))
                    store.save(m)
                }
                .buttonStyle(.link)
                .font(.callout)
                .help(isCurrent
                    ? "Use the rendered 3D thumbnail again"
                    : "Show this image as the thumbnail in the overview")
            }
            Button("Show") { store.revealInFinder(file) }
                .buttonStyle(.link)
                .font(.callout)
        }
        .padding(.leading, indented ? 16 : 0)
        .onHover { hovering in
            guard Model3D.isImage(file) else { return }
            if hovering {
                hoverPreviewFile = file
            } else if hoverPreviewFile == file {
                hoverPreviewFile = nil
            }
        }
        .popover(
            isPresented: Binding(
                get: { hoverPreviewFile == file },
                set: { shown in if !shown, hoverPreviewFile == file { hoverPreviewFile = nil } }
            ),
            arrowEdge: .trailing
        ) {
            ImageHoverPreview(url: file)
        }
    }

    private struct ImageHoverPreview: View {
        let url: URL
        @State private var image: NSImage?

        var body: some View {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .frame(width: 120, height: 120)
                }
            }
            .frame(maxWidth: 360, maxHeight: 360)
            .padding(8)
            .task {
                image = await ThumbnailProvider.shared.imagePreview(for: url)
            }
        }
    }

    private func icon(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "stl", "3mf", "obj", "ply", "usdz": return "cube"
        case "step", "stp", "f3d": return "square.on.circle"
        case "png", "jpg", "jpeg", "heic": return "photo"
        case "gcode": return "printer"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}
