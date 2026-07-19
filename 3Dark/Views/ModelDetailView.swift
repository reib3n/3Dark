import SwiftUI
import UniformTypeIdentifiers

struct ModelDetailView: View {
    @EnvironmentObject private var store: ArchiveStore
    let model: Model3D

    @State private var title: String
    @State private var tagList: [String]
    @State private var collectionList: [String]
    @State private var quelle: String
    @State private var autor: String
    @State private var lizenz: String
    @State private var material: String
    @State private var duese: String
    @State private var schichthoehe: String
    @State private var stuetzen: String
    @State private var gedruckt: String
    @State private var bewertung: Int
    @State private var bodyText: String
    @State private var showMarkdownPreview = false
    @State private var previewFile: URL?
    @State private var hoverPreviewFile: URL?

    init(model: Model3D) {
        self.model = model
        let fm = model.frontmatter
        _title = State(initialValue: fm.string("title").isEmpty ? model.folderURL.lastPathComponent : fm.string("title"))
        _tagList = State(initialValue: fm.tags)
        _collectionList = State(initialValue: fm.list("sammlungen"))
        _quelle = State(initialValue: fm.string("quelle"))
        _autor = State(initialValue: fm.string("autor"))
        _lizenz = State(initialValue: fm.string("lizenz"))
        _material = State(initialValue: fm.string("material"))
        _duese = State(initialValue: fm.string("duese"))
        _schichthoehe = State(initialValue: fm.string("schichthoehe"))
        _stuetzen = State(initialValue: fm.string("stuetzen"))
        _gedruckt = State(initialValue: fm.string("gedruckt"))
        _bewertung = State(initialValue: Int(fm.string("bewertung")) ?? 0)
        _bodyText = State(initialValue: model.body)
    }

    private var appliedModel: Model3D {
        var m = model
        m.frontmatter.setString("title", title)
        m.frontmatter.tags = tagList
        m.frontmatter.setList("sammlungen", collectionList)
        m.frontmatter.setString("quelle", quelle)
        m.frontmatter.setString("autor", autor)
        m.frontmatter.setString("lizenz", lizenz)
        m.frontmatter.setString("material", material)
        m.frontmatter.setString("duese", duese)
        m.frontmatter.setString("schichthoehe", schichthoehe)
        m.frontmatter.setString("stuetzen", stuetzen)
        m.frontmatter.setString("gedruckt", gedruckt)
        m.frontmatter.setString("bewertung", bewertung == 0 ? "" : String(bewertung))
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
                    Label("Im Finder zeigen", systemImage: "folder")
                }
                .help("Modellordner im Finder zeigen")

                Button {
                    if let file = previewFile ?? model.primary3DFile { store.openInCura(file) }
                } label: {
                    Label("In Cura öffnen", systemImage: "printer")
                }
                .help("Angezeigte 3D-Datei an Cura übergeben")
                .disabled(model.primary3DFile == nil)

                Button {
                    store.save(appliedModel)
                } label: {
                    Label("Speichern", systemImage: "square.and.arrow.down")
                }
                .help("Änderungen in model.md speichern (⌘S)")
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
            }
        }
        .navigationTitle(title)
    }

    // MARK: - Metadaten

    private var metadataSection: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            field("Titel", text: $title)
            GridRow {
                Text("Tags")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                TokenField(
                    tokens: $tagList,
                    suggestions: store.tagCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                    placeholder: "Tag hinzufügen …",
                    accent: .blue,
                    icon: "tag",
                    onEdited: save
                )
                .frame(maxWidth: 420, alignment: .leading)
            }
            GridRow {
                Text("Sammlungen")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                TokenField(
                    tokens: $collectionList,
                    suggestions: store.collectionCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                    placeholder: "Sammlung hinzufügen …",
                    accent: .purple,
                    icon: "square.stack.3d.up",
                    onEdited: save
                )
                .frame(maxWidth: 420, alignment: .leading)
            }
            field("Quelle", text: $quelle, prompt: "https://…")
            field("Autor", text: $autor)
            field("Lizenz", text: $lizenz, prompt: "CC BY 4.0")

            GridRow {
                Text("")
                Divider()
            }

            field("Material", text: $material, prompt: "PLA")
            field("Düse", text: $duese, prompt: "0.4")
            field("Schichthöhe", text: $schichthoehe, prompt: "0.2")
            field("Stützen", text: $stuetzen, prompt: "ja / nein")
            field("Gedruckt am", text: $gedruckt, prompt: "JJJJ-MM-TT")

            GridRow {
                Text("Bewertung")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                Picker("Bewertung", selection: $bewertung) {
                    Text("–").tag(0)
                    ForEach(1...5, id: \.self) { stars in
                        Text(String(repeating: "★", count: stars)).tag(stars)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 320, alignment: .leading)
                .onChange(of: bewertung) { _, _ in save() }
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

    /// Übernimmt den aktuellen Formularstand in model.md.
    private func save() {
        store.save(appliedModel)
    }

    // MARK: - Markdown

    private var markdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Beschreibung & Druckhinweise")
                    .font(.headline)
                Spacer()
                Picker("Ansicht", selection: $showMarkdownPreview) {
                    Text("Bearbeiten").tag(false)
                    Text("Vorschau").tag(true)
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

    // MARK: - Dateien

    /// Dateien nach Unterordner gruppiert (Hauptordner zuerst).
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
            Text("Dateien")
                .font(.headline)

            if model.files.isEmpty {
                Text("Noch keine Dateien – zieh STL/3MF-Dateien einfach hierher oder in den Ordner im Finder.")
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
                Text("Tipp: Klick auf ein 3D-Teil zeigt es in der Vorschau; Dateien lassen sich per Drag & Drop hierher kopieren.")
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
                .help("In der 3D-Vorschau anzeigen")
            } else {
                Text(file.lastPathComponent)
            }
            Spacer()
            if Model3D.isPreviewable(file) {
                Button("In Cura öffnen") { store.openInCura(file) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
            if Model3D.isImage(file) {
                let isCurrent = model.frontmatter.string("vorschaubild") == model.relativePath(of: file)
                Button(isCurrent ? "✓ Vorschaubild" : "Als Vorschaubild") {
                    var m = appliedModel
                    m.frontmatter.setString("vorschaubild", isCurrent ? "" : model.relativePath(of: file))
                    store.save(m)
                }
                .buttonStyle(.link)
                .font(.callout)
                .help(isCurrent
                    ? "Wieder das gerenderte 3D-Thumbnail verwenden"
                    : "Dieses Bild in der Übersicht als Vorschaubild zeigen")
            }
            Button("Zeigen") { store.revealInFinder(file) }
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
