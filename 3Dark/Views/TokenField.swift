import SwiftUI

/// Chip-Eingabefeld für Listenwerte (Tags, Sammlungen).
///
/// Vorhandene Werte erscheinen als entfernbare Chips. Neue Werte werden
/// per Texteingabe übernommen (Enter, Komma oder Semikolon) oder über das
/// Plus-Menü aus den bereits im Archiv verwendeten Werten ausgewählt.
struct TokenField: View {
    @Binding var tokens: [String]
    var suggestions: [String]
    var placeholder = "Hinzufügen …"
    var accent: Color = .accentColor
    var icon = "tag"
    /// Wird nach jeder Änderung an den Chips aufgerufen (z. B. zum Speichern).
    var onEdited: () -> Void = {}

    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var availableSuggestions: [String] {
        suggestions.filter { !tokens.contains($0) }
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tokens, id: \.self) { token in
                chip(token)
            }

            HStack(spacing: 4) {
                TextField(placeholder, text: $input)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .frame(minWidth: 90, maxWidth: 180)
                    .onSubmit(commitInput)
                    .onChange(of: input) { _, newValue in
                        if newValue.contains(",") || newValue.contains(";") {
                            commitInput()
                        }
                    }

                if !availableSuggestions.isEmpty {
                    Menu {
                        ForEach(availableSuggestions, id: \.self) { value in
                            Button(value) { add(value) }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Vorhandenen Wert auswählen")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
    }

    private func chip(_ token: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(accent)
            Text(token)
                .font(.callout)
            Button {
                remove(token)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Entfernen")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(accent.opacity(0.16)))
        .overlay(Capsule().strokeBorder(accent.opacity(0.4)))
    }

    private func add(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tokens.contains(trimmed) else { return }
        tokens.append(trimmed)
        onEdited()
    }

    private func remove(_ token: String) {
        tokens.removeAll { $0 == token }
        onEdited()
    }

    private func commitInput() {
        let parts = input.split(whereSeparator: { $0 == "," || $0 == ";" })
        input = ""
        var changed = false
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !tokens.contains(trimmed) {
                tokens.append(trimmed)
                changed = true
            }
        }
        if changed { onEdited() }
    }
}

/// Einfaches umbruchfähiges Layout für die Chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(
            width: maxWidth == .infinity ? usedWidth : maxWidth,
            height: y + rowHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
