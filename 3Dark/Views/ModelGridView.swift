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
                Picker("View", selection: $viewModeRaw) {
                    Label("Grid", systemImage: "square.grid.2x2")
                        .tag(ModelViewMode.grid.rawValue)
                    Label("List", systemImage: "list.bullet")
                        .tag(ModelViewMode.list.rawValue)
                }
                .pickerStyle(.segmented)
                .help("Switch between grid and list view")

                Button {
                    pickAndImport()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import ZIP files or folders as new models")

                Button {
                    onNewModel()
                } label: {
                    Label("New Model", systemImage: "plus")
                }
                .help("Create New Model")
            }
        }
        .overlay {
            if models.isEmpty {
                ContentUnavailableView(
                    "No Models",
                    systemImage: "cube",
                    description: Text("Create a new model with +, import ZIPs/folders via drag & drop, or adjust the filters.")
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

    private func pickAndImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Select ZIP files or folders — each becomes its own model.")
        panel.prompt = String(localized: "Import")
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
        .task(id: [model.previewImageFile, model.primary3DFile]) {
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
        .task(id: [model.previewImageFile, model.primary3DFile]) {
            thumbnail = await ThumbnailProvider.shared.thumbnail(for: model)
        }
    }
}

/// Compact star display (filled = rating, rest hinted).
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
            Text("Create New Model")
                .font(.headline)
            Text("A folder with a model.md will be created in the archive.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Model name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
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
