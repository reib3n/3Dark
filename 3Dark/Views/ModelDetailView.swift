import SwiftUI
import UniformTypeIdentifiers

struct ModelDetailView: View {
    @EnvironmentObject private var store: ArchiveStore
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
                    if let file = previewFile ?? model.primary3DFile { store.openInCura(file) }
                } label: {
                    Label("Open in Cura", systemImage: "printer")
                }
                .help("Send the displayed 3D file to Cura")
                .disabled(model.primary3DFile == nil)

                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save changes to model.md (⌘S)")
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
            }
        }
        .navigationTitle(title)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            field("Title", text: $title)

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
            field("Source", text: $source, prompt: "https://…")
            field("Author", text: $author)
            field("License", text: $license, prompt: "CC BY 4.0")

            GridRow {
                Text("")
                Divider()
            }

            field("Material", text: $material, prompt: "PLA")
            field("Nozzle", text: $nozzle, prompt: "0.4")
            field("Layer height", text: $layerHeight, prompt: "0.2")
            field("Supports", text: $supports, prompt: "yes / no")
            field("Printed on", text: $printed, prompt: "YYYY-MM-DD")

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
            if Model3D.isPreviewable(file) {
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
        case "png", "jpg", "jpeg", "heic": return "photo"
        case "gcode": return "printer"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}
