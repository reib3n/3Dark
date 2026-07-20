import SwiftUI

/// Shown right after an import when a freshly imported model duplicates
/// an existing one: keep it or discard the new copy. Discarding only
/// removes the copy inside the archive — the source stays untouched.
struct ImportDuplicatesView: View {
    @EnvironmentObject private var store: ArchiveStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Duplicates Imported", systemImage: "doc.on.doc")
                .font(.headline)

            Text("These imports have the same file contents as models already in your archive. Discarding removes only the new copy — the original files you imported from stay untouched.")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.pendingImportDuplicates) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "cube.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text(entry.imported.title)
                                    .fontWeight(.semibold)
                                Spacer()
                                Button("Keep") {
                                    store.pendingImportDuplicates.removeAll { $0.id == entry.id }
                                }
                                .buttonStyle(.link)
                                Button("Discard Import", role: .destructive) {
                                    store.discardImport(entry.imported)
                                }
                                .buttonStyle(.link)
                            }
                            Text("Already in archive: \(entry.matches.map(\.title).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)

            HStack {
                Button("Discard All") {
                    for entry in store.pendingImportDuplicates {
                        store.discardImport(entry.imported)
                    }
                }
                Spacer()
                Button("Keep All") {
                    store.pendingImportDuplicates.removeAll()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onChange(of: store.pendingImportDuplicates.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }
}
