import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: ArchiveStore
    @Binding var selectedTags: Set<String>
    @Binding var selectedCollection: String?
    @Binding var matchAll: Bool
    @Binding var minRating: Int

    var body: some View {
        List {
            Section {
                Button {
                    selectedTags.removeAll()
                    selectedCollection = nil
                    minRating = 0
                } label: {
                    HStack {
                        Label("All Models", systemImage: "square.grid.2x2")
                        Spacer()
                        Text("\(store.models.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }

            let collectionCounts = store.collectionCounts
            if !collectionCounts.isEmpty {
                Section("Collections") {
                    ForEach(collectionCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { collection in
                        Button {
                            selectedCollection = selectedCollection == collection ? nil : collection
                        } label: {
                            HStack {
                                Image(systemName: selectedCollection == collection ? "checkmark.circle.fill" : "square.stack.3d.up")
                                    .foregroundStyle(selectedCollection == collection ? Color.accentColor : .secondary)
                                Text(collection)
                                Spacer()
                                Text("\(collectionCounts[collection] ?? 0)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Tags") {
                let counts = store.tagCounts
                if counts.isEmpty {
                    Text("No tags yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { tag in
                        Button {
                            toggle(tag)
                        } label: {
                            HStack {
                                Image(systemName: selectedTags.contains(tag) ? "checkmark.circle.fill" : "tag")
                                    .foregroundStyle(selectedTags.contains(tag) ? Color.accentColor : .secondary)
                                Text(tag)
                                Spacer()
                                Text("\(counts[tag] ?? 0)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Rating") {
                ForEach((1...5).reversed(), id: \.self) { stars in
                    let count = store.models.filter { $0.rating >= stars }.count
                    Button {
                        minRating = minRating == stars ? 0 : stars
                    } label: {
                        HStack {
                            Image(systemName: minRating == stars ? "checkmark.circle.fill" : "star")
                                .foregroundStyle(minRating == stars ? Color.accentColor : .secondary)
                            RatingStars(rating: stars)
                            Text("and up")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedTags.count > 1 {
                Section("Combination") {
                    Picker("Combination", selection: $matchAll) {
                        Text("OR – any tag matches").tag(false)
                        Text("AND – all tags").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let root = store.rootURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text(root.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(root.path)
                    Button("Change Folder…") {
                        store.chooseRootFolder()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.bar)
            }
        }
    }

    private func toggle(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}
