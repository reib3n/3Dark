import SwiftUI

/// Chip input field for list values (tags, collections).
///
/// Existing values appear as removable chips. New values are committed
/// via text entry (Enter, comma, or semicolon) or picked from the values
/// already used across the archive via the plus menu.
struct TokenField: View {
    @Binding var tokens: [String]
    var suggestions: [String]
    var placeholder: LocalizedStringKey = "Add…"
    var accent: Color = .accentColor
    var icon = "tag"
    /// Called after every chip change (e.g. to save).
    var onEdited: () -> Void = {}

    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var availableSuggestions: [String] {
        suggestions.filter { !tokens.contains($0) }
    }

    /// Typeahead matches while typing (contains, case-insensitive).
    private var typeaheadMatches: [String] {
        let query = input.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return Array(
            availableSuggestions
                .filter { $0.localizedCaseInsensitiveContains(query) && $0.caseInsensitiveCompare(query) != .orderedSame }
                .prefix(5)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            tokenArea
            if !typeaheadMatches.isEmpty {
                HStack(spacing: 6) {
                    ForEach(typeaheadMatches, id: \.self) { match in
                        Button {
                            add(match)
                            input = ""
                        } label: {
                            Text(match)
                                .font(.callout)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .help("Accept")
                    }
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

    private var tokenArea: some View {
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
                    .help("Choose an existing value")
                }
            }
        }
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
            .help("Remove")
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

/// Simple wrapping layout for the chips.
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
