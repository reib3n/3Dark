import SwiftUI

struct ModelGridView: View {
    let models: [Model3D]
    @Binding var selectedID: Model3D.ID?
    var onNewModel: () -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 16)],
                spacing: 16
            ) {
                ForEach(models) { model in
                    ModelCell(model: model, isSelected: model.id == selectedID)
                        .onTapGesture { selectedID = model.id }
                }
            }
            .padding()
        }
        .navigationTitle("3Dark")
        .toolbar {
            Button {
                onNewModel()
            } label: {
                Label("Neues Modell", systemImage: "plus")
            }
            .help("Neues Modell anlegen")
        }
        .overlay {
            if models.isEmpty {
                ContentUnavailableView(
                    "Keine Modelle",
                    systemImage: "cube",
                    description: Text("Lege mit + ein neues Modell an oder passe die Filter an.")
                )
            }
        }
    }
}

private struct ModelCell: View {
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
