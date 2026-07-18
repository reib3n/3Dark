import Foundation

struct FrontmatterField: Equatable, Hashable {
    var key: String
    var value: String
}

/// YAML-Frontmatter einer model.md-Datei.
///
/// Bewusst kein vollständiger YAML-Parser: unterstützt werden Skalare
/// (`key: wert`), Inline-Listen (`key: [a, b]`) und einfache Block-Listen.
/// Unbekannte Felder bleiben beim Speichern unverändert erhalten.
struct Frontmatter: Equatable, Hashable {
    var fields: [FrontmatterField] = []

    subscript(key: String) -> String? {
        get { fields.first(where: { $0.key == key })?.value }
        set {
            if let newValue, !newValue.isEmpty {
                if let index = fields.firstIndex(where: { $0.key == key }) {
                    fields[index].value = newValue
                } else {
                    fields.append(FrontmatterField(key: key, value: newValue))
                }
            } else {
                fields.removeAll { $0.key == key }
            }
        }
    }

    /// Skalarwert ohne umschließende Anführungszeichen (für Anzeige/Bearbeitung).
    func string(_ key: String) -> String {
        Frontmatter.unquote(self[key] ?? "")
    }

    /// Setzt einen Skalar; leerer Wert entfernt das Feld.
    mutating func setString(_ key: String, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        self[key] = trimmed.isEmpty ? nil : Frontmatter.quoteIfNeeded(trimmed)
    }

    /// Listenwert (`key: [a, b]` bzw. Block-Liste) als String-Array.
    /// Als Trenner wird neben Komma auch Semikolon akzeptiert,
    /// damit handgeschriebene Dateien tolerant gelesen werden.
    func list(_ key: String) -> [String] {
        guard let raw = self[key] else { return [] }
        var inner = raw.trimmingCharacters(in: .whitespaces)
        if inner.hasPrefix("["), inner.hasSuffix("]") {
            inner = String(inner.dropFirst().dropLast())
        }
        return inner.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { Frontmatter.unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    /// Setzt eine Inline-Liste; leere Liste entfernt das Feld,
    /// außer `keepEmpty` verlangt ein explizites `[]`.
    mutating func setList(_ key: String, _ values: [String], keepEmpty: Bool = false) {
        if values.isEmpty, !keepEmpty {
            self[key] = nil
        } else {
            self[key] = "[" + values.joined(separator: ", ") + "]"
        }
    }

    var tags: [String] {
        get { list("tags") }
        set { setList("tags", newValue, keepEmpty: true) }
    }

    // MARK: - Parsen & Serialisieren

    static func parse(document: String) -> (frontmatter: Frontmatter, body: String) {
        let lines = document.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (Frontmatter(), document)
        }

        var frontmatter = Frontmatter()
        var pendingKey: String?
        var pendingItems: [String] = []
        var bodyStart: Int?

        func flushPending() {
            guard let key = pendingKey else { return }
            frontmatter.fields.append(
                FrontmatterField(key: key, value: "[" + pendingItems.joined(separator: ", ") + "]")
            )
            pendingKey = nil
            pendingItems = []
        }

        var index = 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if trimmed == "---" {
                flushPending()
                bodyStart = index
                break
            }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("- "), pendingKey != nil {
                pendingItems.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                continue
            }
            flushPending()
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                pendingKey = key
            } else {
                frontmatter.fields.append(FrontmatterField(key: key, value: value))
            }
        }

        guard var start = bodyStart else {
            return (Frontmatter(), document)
        }
        if start < lines.count, lines[start].isEmpty { start += 1 }
        let body = lines[start...].joined(separator: "\n")
        return (frontmatter, body)
    }

    func serialized(body: String) -> String {
        var output = "---\n"
        for field in fields {
            output += "\(field.key): \(field.value)\n"
        }
        output += "---\n\n"
        output += body.trimmingCharacters(in: .whitespacesAndNewlines)
        output += "\n"
        return output
    }

    // MARK: - Helfer

    static func unquote(_ value: String) -> String {
        var v = value
        if v.count >= 2,
           (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v.replacingOccurrences(of: "\\\"", with: "\"")
    }

    static func quoteIfNeeded(_ value: String) -> String {
        let needsQuoting = value.contains(":") || value.contains("#")
            || value.hasPrefix("[") || value.hasPrefix("\"") || value.hasPrefix("'")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
