import SwiftUI

/// On-demand duplicate scan: hashes the archive's 3D files and lists
/// models that share identical content. Never runs automatically.
struct DuplicatesView: View {
    @EnvironmentObject private var store: ArchiveStore
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case confirm
        case scanning
        case finished
    }

    @State private var phase: Phase = .confirm
    @State private var scanned = 0
    @State private var result = DuplicateFinder.ScanResult()

    private var groups: [DuplicateFinder.DuplicateGroup] { result.groups }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Find Duplicates", systemImage: "doc.on.doc")
                .font(.headline)

            switch phase {
            case .confirm:
                Text("Hashes and compares every 3D file in the archive — including all existing models, which are hashed on the first run. Large archives on network or cloud volumes can take a moment.")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Start") { scan() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            case .scanning:
                ProgressView(value: Double(scanned), total: Double(max(store.models.count, 1))) {
                    Text("Scanning \(scanned) of \(store.models.count)…")
                }
            case .finished:
                Text("Analyzed \(result.totalFiles) 3D files — \(result.hashedFiles) newly hashed, \(result.cachedFiles) from cache.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if groups.isEmpty {
                    Label("No duplicates found.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Text("\(groups.count) groups of models share identical files.")
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(group.models) { model in
                                        HStack(spacing: 8) {
                                            Image(systemName: "cube")
                                                .foregroundStyle(.secondary)
                                            Text(model.title)
                                            Spacer()
                                            Button("Show") { store.revealInFinder(model.folderURL) }
                                                .buttonStyle(.link)
                                                .font(.callout)
                                            Button("Move to Trash") { store.moveToTrash(model) }
                                                .buttonStyle(.link)
                                                .font(.callout)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                }
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func scan() {
        phase = .scanning
        let models = store.models
        Task {
            let found = await DuplicateFinder.shared.scan(models: models) { count in
                Task { @MainActor in scanned = count }
            }
            result = found
            phase = .finished
        }
    }
}
