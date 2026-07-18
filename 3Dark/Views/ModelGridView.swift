import SwiftUI
import AppKit

enum ModelViewMode: String, CaseIterable {
    case grid
    case list
}

struct ModelBrowserView: View {
    @EnvironmentObject private var store: ArchiveStore
    let models: [Model3D]
    @Binding var selectedID: Model3D.ID?
    var onNewModel: () -> Void

    @AppStorage("ModelViewMode") private var viewModeRaw = ModelViewMode.grid.rawValue

    private var viewMode: ModelViewMode {
        ModelViewMode(rawValue: viewModeRaw) ?? .grid
    }

    var body: some View {
        Group {
            switch viewMode {
            case .grid: gridView
            case .list: listView
            }
        }
        .navigationTitle("3Dark")
        .toolbar {
            ToolbarItemGroup {
                Picker("Ansicht", selection: $viewModeRaw) {
                    Label("Raster", systemImage: "square.grid.2x2")
                        .tag(ModelViewMode.grid.rawValue)
                    Label("Liste", systemImage: "list.bullet")
                        .tag(ModelViewMode.list.rawValue)
                }
                .pickerStyle(.segmented)
                .help("Zwischen Raster- und Listenansicht umschalten")

                Button {
                    pickAndImport()
                } label: {
                    Label("Importieren", systemImage: "square.and.arrow.down")
                }
                .help("ZIP-Dateien oder Ordner als neue Modelle importieren")

                Button {
                    onNewModel()
                } label: {
                    Label("Neues Modell", systemImage: "plus")
                }
                .help("Neues Modell anlegen")
            }
        }
        .overlay {
            if models.isEmpty {
                ContentUnavailableView(
                    "Keine Modelle",
                    systemImage: "cube",
                    description: Text("Lege mit + ein neues Modell an, importiere ZIPs/Ordner per Drag & Drop oder passe die Filter an.")
                )
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let fileURLs = urls.filter { $0.isFileURL }
            guard !fileURLs.isEmpty else { return false }
            importAndSelect(fileURLs)
            return true
        }
    }

    private func pickAndImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "ZIP-Dateien oder Ordner auswählen — jede Auswahl wird ein eigenes Modell."
        panel.prompt = "Importieren"
        if panel.runModal() == .OK {
            importAndSelect(panel.urls)
        }
    }

    private func importAndSelect(_ urls: [URL]) {
        let imported = store.importModels(from: urls)
        if let last = imported.last {
            selectedID = last.id
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 16)],
                spacing: 16
            ) {
                ForEach(models) { model in
                    ModelGridCell(model: model, isSelected: model.id == selectedID)
                        .onTapGesture { selectedID = model.id }
                }
            }
            .padding()
        }
    }

    private var listView: some View {
        List(selection: $selectedID) {
            ForEach(models) { model in
                ModelListRow(model: model)
                    .tag(model.id)
            }
        }
        .listStyle(.inset)
    }
}

private struct ModelGridCell: View {
    let model: Model3D
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "cube")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(model.title)
                .font(.headline)
                .lineLimit(1)

            if model.rating > 0 {
                RatingStars(rating: model.rating)
            }

            if !model.tags.isEmpty {
                Text(model.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .task(id: model.primary3DFile) {
            thumbnail = await ThumbnailProvider.shared.thumbnail(for: model)
        }
    }
}

private struct ModelListRow: View {
    let model: Model3D
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.06))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "cube")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !model.collections.isEmpty {
                        Label(model.collections.joined(separator: ", "), systemImage: "square.stack.3d.up")
                            .labelStyle(.titleAndIcon)
                    }
                    if !model.tags.isEmpty {
                        Text(model.tags.joined(separator: " · "))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if model.rating > 0 {
                RatingStars(rating: model.rating)
            }
        }
        .padding(.vertical, 2)
        .task(id: model.primary3DFile) {
            thumbnail = await ThumbnailProvider.shared.thumbnail(for: model)
        }
    }
}

/// Kompakte Sterne-Anzeige (gefüllt = Bewertung, Rest angedeutet).
struct RatingStars: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(star <= rating ? Color.orange : Color.secondary.opacity(0.4))
            }
        }
    }
}

struct NewModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var onCreate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Neues Modell anlegen")
                .font(.headline)
            Text("Es wird ein Ordner mit einer model.md im Archiv erstellt.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Name des Modells", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Anlegen", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
        dismiss()
    }
}
