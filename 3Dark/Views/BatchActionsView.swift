import SwiftUI

/// Shown in the detail column while several models are selected:
/// apply tags or collections to all of them at once, or trash them.
struct BatchActionsView: View {
    @EnvironmentObject private var store: ArchiveStore
    let models: [Model3D]
    var onDone: () -> Void

    @State private var tagDraft = ""
    @State private var collectionDraft = ""
    @State private var showingTrashConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("\(models.count) models selected", systemImage: "square.stack")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add tag to all")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        TextField("", text: $tagDraft, prompt: Text("Add tag…"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                            .onSubmit(applyTag)
                        Button("Apply", action: applyTag)
                            .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    suggestionRow(store.tagCounts, draft: $tagDraft)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add to collection")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        TextField("", text: $collectionDraft, prompt: Text("Add collection…"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                            .onSubmit(applyCollection)
                        Button("Apply", action: applyCollection)
                            .disabled(collectionDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    suggestionRow(store.collectionCounts, draft: $collectionDraft)
                }

                Divider()

                Button(role: .destructive) {
                    showingTrashConfirmation = true
                } label: {
                    Label("Move all to Trash", systemImage: "trash")
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(models) { model in
                        Text(model.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding()
        }
        .alert("Move all to Trash?", isPresented: $showingTrashConfirmation) {
            Button("Move to Trash", role: .destructive) {
                store.moveToTrash(models)
                onDone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(models.count) models are moved to the deleted folder inside the archive.")
        }
        .navigationTitle("Multiple Selection")
    }

    /// Existing values as one-click chips — same idea as the typeahead
    /// in the single-model editor.
    @ViewBuilder
    private func suggestionRow(_ counts: [String: Int], draft: Binding<String>) -> some View {
        let available = counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.prefix(8)
        if !available.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(available), id: \.self) { value in
                    Button {
                        draft.wrappedValue = value
                    } label: {
                        Text(value)
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func applyTag() {
        store.addTag(tagDraft, to: models)
        tagDraft = ""
    }

    private func applyCollection() {
        store.addCollection(collectionDraft, to: models)
        collectionDraft = ""
    }
}
