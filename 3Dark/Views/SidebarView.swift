import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: ArchiveStore
    @Binding var selectedTags: Set<String>
    @Binding var matchAll: Bool

    var body: some View {
        List {
            Section {
                Button {
                    selectedTags.removeAll()
                } label: {
                    HStack {
                        Label("Alle Modelle", systemImage: "square.grid.2x2")
                        Spacer()
                        Text("\(store.models.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Tags") {
                let counts = store.tagCounts
                if counts.isEmpty {
                    Text("Noch keine Tags")
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

            if selectedTags.count > 1 {
                Section("Verknüpfung") {
                    Picker("Verknüpfung", selection: $matchAll) {
                        Text("ODER – ein Tag genügt").tag(false)
                        Text("UND – alle Tags").tag(true)
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
                    Button("Ordner wechseln …") {
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
