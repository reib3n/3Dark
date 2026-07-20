import SwiftUI

/// Print history editor. Entries live as a markdown table in the
/// model.md body, so they stay readable without the app.
struct PrintLogSection: View {
    @Binding var entries: [PrintLogEntry]
    var onCommit: () -> Void

    @State private var draft = PrintLogEntry.empty()
    @State private var showingForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Print History")
                    .font(.headline)
                Spacer()
                Button {
                    draft = PrintLogEntry.empty()
                    showingForm.toggle()
                } label: {
                    Label("Add Print", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.link)
            }

            if entries.isEmpty, !showingForm {
                Text("No prints recorded yet. Note material, settings and outcome here — that's the knowledge you'll want back in a year.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !entries.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Date").gridColumnAlignment(.leading)
                        Text("Material")
                        Text("Printer")
                        Text("Settings")
                        Text("Result")
                        Text("")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        GridRow {
                            Text(entry.date).monospacedDigit()
                            Text(entry.material)
                            Text(entry.printer)
                            Text(entry.settings)
                            Text(entry.result)
                            Button {
                                entries.remove(at: index)
                                onCommit()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                        .font(.callout)
                        if !entry.notes.isEmpty {
                            GridRow {
                                Text("")
                                Text(entry.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .gridCellColumns(5)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            if showingForm {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("Date", text: $draft.date, prompt: Text("YYYY-MM-DD"))
                            .frame(width: 100)
                        TextField("Material", text: $draft.material, prompt: Text("PLA"))
                            .frame(width: 90)
                        TextField("Printer", text: $draft.printer, prompt: Text("Printer"))
                            .frame(width: 110)
                        TextField("Settings", text: $draft.settings, prompt: Text("0.2 mm, 20%"))
                    }
                    HStack(spacing: 6) {
                        TextField("Result", text: $draft.result, prompt: Text("OK / failed"))
                            .frame(width: 120)
                        TextField("Notes", text: $draft.notes, prompt: Text("What to remember next time"))
                        Button("Cancel") { showingForm = false }
                            .buttonStyle(.link)
                        Button("Save") { commitDraft() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(draft.date.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitDraft)
                .padding(8)
                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func commitDraft() {
        guard !draft.date.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        entries.append(draft)
        showingForm = false
        onCommit()
    }
}
