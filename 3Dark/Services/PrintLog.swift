import Foundation

/// One recorded print attempt.
struct PrintLogEntry: Identifiable, Equatable {
    var date: String
    var material: String
    var printer: String
    var settings: String
    var result: String
    var notes: String

    var id: String { date + material + printer + settings + result + notes }

    static func empty() -> PrintLogEntry {
        PrintLogEntry(
            date: Model3D.addedFormatter.string(from: Date()),
            material: "", printer: "", settings: "", result: "", notes: ""
        )
    }
}

/// Reads and writes the print history as a markdown table inside the
/// model.md body — so the log stays readable and editable without the
/// app, like every other piece of model documentation.
enum PrintLog {
    /// Fixed English marker, like the `## Description` section the app
    /// writes: it is a parsing anchor, not display text.
    static let sectionTitle = "## Print Log"
    private static let header = "| Date | Material | Printer | Settings | Result | Notes |"
    private static let separator = "|---|---|---|---|---|---|"

    static func parse(body: String) -> [PrintLogEntry] {
        let lines = body.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionTitle }) else {
            return []
        }
        var entries: [PrintLogEntry] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") { break }
            guard trimmed.hasPrefix("|") else { continue }
            let cells = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // Skip the header and the |---|---| separator row.
            guard cells.count >= 6,
                  cells[0].lowercased() != "date",
                  !cells[0].allSatisfy({ $0 == "-" || $0 == ":" }) else { continue }
            entries.append(PrintLogEntry(
                date: cells[0], material: cells[1], printer: cells[2],
                settings: cells[3], result: cells[4], notes: cells[5]
            ))
        }
        return entries
    }

    /// Replaces (or appends) the print log section, leaving the rest of
    /// the body untouched.
    static func write(_ entries: [PrintLogEntry], into body: String) -> String {
        var lines = body.components(separatedBy: "\n")

        if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionTitle }) {
            var end = lines.count
            for index in (start + 1)..<lines.count where lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("## ") {
                end = index
                break
            }
            lines.removeSubrange(start..<end)
            if entries.isEmpty {
                // Drop trailing blank lines the removal left behind.
                while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 {
                    lines.removeLast()
                }
                return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            }
            lines.insert(contentsOf: section(for: entries), at: start)
            return lines.joined(separator: "\n")
        }

        guard !entries.isEmpty else { return body }
        var result = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty { result += "\n\n" }
        result += section(for: entries).joined(separator: "\n")
        return result
    }

    private static func section(for entries: [PrintLogEntry]) -> [String] {
        var lines = [sectionTitle, "", header, separator]
        for entry in entries {
            let cells = [entry.date, entry.material, entry.printer, entry.settings, entry.result, entry.notes]
                .map { $0.replacingOccurrences(of: "|", with: "/") }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        lines.append("")
        return lines
    }
}
