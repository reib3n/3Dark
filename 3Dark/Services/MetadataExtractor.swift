import Foundation

/// Deterministic stage-1 metadata extraction from the text files that
/// come with an import (portal readmes, license files).
///
/// Precision over recall: only unambiguous patterns are used and only
/// empty front matter fields are filled. Print settings are deliberately
/// never guessed from free text — a wrong `supports: no` is worse than
/// an empty field.
enum MetadataExtractor {
    struct Extracted {
        var title: String?
        var source: String?
        var author: String?
        var license: String?
    }

    /// Hosts whose URLs are treated as the model's source with
    /// near-certainty.
    private static let portalHosts = [
        "printables.com",
        "thingiverse.com",
        "makerworld.com",
        "myminifactory.com",
        "cults3d.com",
        "thangs.com",
    ]

    static func extract(from text: String) -> Extracted {
        var result = Extracted()
        let lines = text.components(separatedBy: .newlines)

        result.source = firstPortalURL(in: text)

        // Thingiverse readme headline:
        // "<Title> by <author> on Thingiverse: <url>"
        for line in lines {
            if let match = line.firstMatch(of: #/^(.{3,120}?) by (\S{2,60}) on Thingiverse/#) {
                result.title = String(match.1).cleanedValue
                result.author = String(match.2).cleanedValue
                break
            }
        }

        // Labeled lines ("Author: xyz", "Designer: xyz", …).
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).cleanedValue
            guard !value.isEmpty, value.count <= 200, !value.lowercased().hasPrefix("http") else {
                continue
            }
            switch label {
            case "author", "designer", "creator", "designed by":
                if result.author == nil { result.author = value }
            case "model name", "title", "model":
                if result.title == nil { result.title = value }
            case "license", "licence":
                if result.license == nil {
                    // Prefer the normalized short code; fall back to the
                    // raw value only when it is short and label-explicit.
                    result.license = normalizedLicense(in: value) ?? (value.count <= 60 ? value : nil)
                }
            default:
                break
            }
        }

        // License mentioned somewhere in prose (e.g. Thingiverse footer).
        if result.license == nil {
            for line in lines {
                if let license = normalizedLicense(in: line) {
                    result.license = license
                    break
                }
            }
        }

        return result
    }

    // MARK: - Patterns

    private static func firstPortalURL(in text: String) -> String? {
        let matches = text.matches(of: #/https?://[A-Za-z0-9./_%#?=&:+~-]+/#)
        for match in matches {
            var url = String(match.0)
            while let last = url.last, ".,);]".contains(last) {
                url.removeLast()
            }
            guard let host = URL(string: url)?.host?.lowercased() else { continue }
            if portalHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                return url
            }
        }
        return nil
    }

    /// Normalizes Creative Commons and a few other well-known licenses
    /// to their short identifier. Analyzes a single line so that stray
    /// "SA"/"ND" tokens elsewhere in the text cannot interfere.
    /// Also used by the AI enrichment validator.
    static func normalizedLicense(in line: String) -> String? {
        let lower = line.lowercased()

        if lower.contains("cc0") || lower.contains("creative commons zero") {
            return "CC0"
        }

        let isCreativeCommons = lower.contains("creative commons")
            || lower.range(of: #"\bcc[- ]?by\b"#, options: .regularExpression) != nil
        if isCreativeCommons {
            let hasAttribution = lower.contains("attribution")
                || lower.range(of: #"\bcc[- ]?by\b"#, options: .regularExpression) != nil
            guard hasAttribution else { return nil }
            let nc = lower.contains("noncommercial") || lower.contains("non-commercial")
                || lower.contains("non commercial")
                || lower.range(of: #"\bnc\b"#, options: .regularExpression) != nil
            let nd = lower.contains("noderivat") || lower.contains("no derivatives")
                || lower.range(of: #"\bnd\b"#, options: .regularExpression) != nil
            let sa = lower.contains("sharealike") || lower.contains("share-alike")
                || lower.contains("share alike")
                || lower.range(of: #"\bsa\b"#, options: .regularExpression) != nil

            var code = "CC BY"
            if nc { code += "-NC" }
            if nd {
                code += "-ND"
            } else if sa {
                code += "-SA"
            }
            if let versionRange = lower.range(of: #"\b[1-4]\.0\b"#, options: .regularExpression) {
                code += " " + lower[versionRange]
            }
            return code
        }

        if lower.contains("mit license") || lower.contains("mit licence") {
            return "MIT"
        }
        if lower.contains("standard digital file license") {
            return "Standard Digital File License"
        }
        return nil
    }
}

private extension String {
    /// Trimmed, with markdown emphasis leftovers removed.
    var cleanedValue: String {
        trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*_"))
            .trimmingCharacters(in: .whitespaces)
    }
}
