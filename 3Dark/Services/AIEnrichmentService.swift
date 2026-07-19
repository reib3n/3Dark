import Foundation

/// Suggested metadata produced by AI enrichment. Stored under `ai_*`
/// front matter keys — never written to the canonical fields.
struct AISuggestions {
    var fields: [String: String] = [:]
    var tags: [String] = []

    var isEmpty: Bool { fields.isEmpty && tags.isEmpty }
}

enum AIEnrichmentError: LocalizedError {
    case noSource
    case noAPIKey
    case pageLoadFailed(String)
    case apiFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSource:
            return String(localized: "No source link set.")
        case .noAPIKey:
            return String(localized: "No API key set. Add one in Settings.")
        case .pageLoadFailed(let detail):
            return String(localized: "Could not load the source page: \(detail)")
        case .apiFailed(let detail):
            return String(localized: "The AI request failed: \(detail)")
        }
    }
}

/// Enriches a model's metadata from its source page.
///
/// Pipeline: fetch the page → deterministic extraction from embedded
/// JSON-LD (exact, free) → Claude API with a strict JSON schema for the
/// remaining fields → hard validation. Only the page text and the names
/// of missing fields leave the machine; results are stored as `ai_*`
/// fields and never overwrite existing values.
actor AIEnrichmentService {
    static let shared = AIEnrichmentService()

    static let apiKeyAccount = "anthropic-api-key"
    /// Extraction is a simple task — Haiku is sufficient and cheap.
    static let claudeModel = "claude-haiku-4-5"
    /// Front matter fields the enrichment may suggest values for.
    static let enrichableFields = ["author", "license", "material", "nozzle", "layer_height", "supports"]

    private static let maxPageTextChars = 30_000
    private static let maxTags = 6

    static var hasAPIKey: Bool {
        !(KeychainStore.string(for: apiKeyAccount) ?? "").isEmpty
    }

    /// Models eligible for batch enrichment: they have an http(s) source
    /// link, at least one enrichable field is still empty, and they have
    /// not been checked by the AI before (`ai_updated` unset — a check
    /// with zero findings counts too). Single-model enrichment ignores
    /// this and can always re-check.
    static func candidates(in models: [Model3D]) -> [Model3D] {
        models.filter { model in
            let source = model.frontmatter.string("source").lowercased()
            guard source.hasPrefix("http://") || source.hasPrefix("https://") else { return false }
            guard model.frontmatter.string("ai_updated").isEmpty else { return false }
            return enrichableFields.contains { model.frontmatter.string($0).isEmpty }
        }
    }

    func enrich(model: Model3D) async throws -> AISuggestions {
        let sourceString = model.frontmatter.string("source")
        guard let url = URL(string: sourceString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw AIEnrichmentError.noSource
        }
        guard let apiKey = KeychainStore.string(for: Self.apiKeyAccount), !apiKey.isEmpty else {
            throw AIEnrichmentError.noAPIKey
        }

        let missingFields = Self.enrichableFields.filter { model.frontmatter.string($0).isEmpty }
        let html = try await fetchPage(url)

        // Deterministic pass first: JSON-LD on portal pages is exact.
        var fields: [String: String] = [:]
        let structured = Self.jsonLDValues(fromHTML: html)
        for (key, value) in structured where missingFields.contains(key) {
            if let valid = Self.validated(field: key, value: value) {
                fields[key] = valid
            }
        }

        // LLM pass for whatever is still missing (plus tag suggestions).
        let stillMissing = missingFields.filter { fields[$0] == nil }
        let pageText = Self.pageText(fromHTML: html)
        let raw = try await callClaude(
            apiKey: apiKey,
            pageText: pageText,
            missingFields: stillMissing,
            existingTags: model.tags
        )

        for field in stillMissing {
            if let value = raw[field] as? String,
               let valid = Self.validated(field: field, value: value) {
                fields[field] = valid
            }
        }

        var tags: [String] = []
        if let rawTags = raw["tags"] as? [String] {
            tags = rawTags
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count <= 30 }
                .filter { candidate in !model.tags.contains { $0.lowercased() == candidate.lowercased() } }
            tags = Array(tags.prefix(Self.maxTags))
        }

        return AISuggestions(fields: fields, tags: tags)
    }

    // MARK: - Page fetching & parsing

    private func fetchPage(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIEnrichmentError.pageLoadFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AIEnrichmentError.pageLoadFailed("HTTP \(http.statusCode)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Exact values from embedded JSON-LD (`name`, `author`, `license`).
    static func jsonLDValues(fromHTML html: String) -> [String: String] {
        var result: [String: String] = [:]
        let scriptRegex = #/<script[^>]*application\/ld\+json[^>]*>(.*?)<\/script>/#.dotMatchesNewlines()

        func harvest(_ object: [String: Any]) {
            if result["author"] == nil {
                if let author = object["author"] as? String {
                    result["author"] = author
                } else if let author = object["author"] as? [String: Any],
                          let name = author["name"] as? String {
                    result["author"] = name
                }
            }
            if result["license"] == nil, let license = object["license"] as? String {
                if let normalized = license.hasPrefix("http")
                    ? Self.license(fromURL: license)
                    : MetadataExtractor.normalizedLicense(in: license) {
                    result["license"] = normalized
                }
            }
        }

        for match in html.matches(of: scriptRegex) {
            guard let data = String(match.1).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let object = json as? [String: Any] {
                harvest(object)
            } else if let array = json as? [[String: Any]] {
                array.forEach(harvest)
            }
        }
        return result
    }

    /// Maps Creative Commons license URLs to their short identifier.
    static func license(fromURL url: String) -> String? {
        let lower = url.lowercased()
        if lower.contains("publicdomain/zero") || lower.contains("/cc0") {
            return "CC0"
        }
        guard let match = lower.firstMatch(of: #/creativecommons\.org\/licenses\/([a-z-]+)\/([0-9.]+)/#) else {
            return nil
        }
        return "CC " + match.1.uppercased() + " " + match.2
    }

    /// Strips scripts, styles, and tags; decodes common entities.
    static func pageText(fromHTML html: String) -> String {
        var text = html
        text = text.replacing(#/<script[^>]*>.*?<\/script>/#.dotMatchesNewlines(), with: " ")
        text = text.replacing(#/<style[^>]*>.*?<\/style>/#.dotMatchesNewlines(), with: " ")
        text = text.replacing(#/<[^>]+>/#, with: " ")
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacing(#/\s+/#, with: " ").trimmingCharacters(in: .whitespaces)
        return String(text.prefix(maxPageTextChars))
    }

    // MARK: - Validation

    /// Hard validation: anything that fails is dropped, never "repaired".
    static func validated(field: String, value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return nil }

        switch field {
        case "license":
            return MetadataExtractor.normalizedLicense(in: trimmed)
        case "nozzle":
            guard let number = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
                  (0.1...1.5).contains(number) else { return nil }
            return trimmed.replacingOccurrences(of: ",", with: ".")
        case "layer_height":
            guard let number = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
                  (0.03...0.8).contains(number) else { return nil }
            return trimmed.replacingOccurrences(of: ",", with: ".")
        case "supports":
            switch trimmed.lowercased() {
            case "yes", "ja", "true", "required": return "yes"
            case "no", "nein", "false", "none", "not required": return "no"
            default: return nil
            }
        case "material":
            guard (2...40).contains(trimmed.count) else { return nil }
            return trimmed
        case "author":
            guard (2...80).contains(trimmed.count), !trimmed.lowercased().hasPrefix("http") else { return nil }
            return trimmed
        default:
            return nil
        }
    }

    // MARK: - Claude API (raw HTTP; no official Swift SDK exists)

    /// Constant schema so the API's 24h schema cache applies across calls.
    private static let outputSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["author", "license", "material", "nozzle", "layer_height", "supports", "tags"],
        "properties": [
            "author": ["type": ["string", "null"]],
            "license": ["type": ["string", "null"]],
            "material": ["type": ["string", "null"]],
            "nozzle": ["type": ["string", "null"]],
            "layer_height": ["type": ["string", "null"]],
            "supports": ["type": ["string", "null"], "description": "\"yes\" or \"no\""],
            "tags": ["type": "array", "items": ["type": "string"]],
        ],
    ]

    private static let systemPrompt = """
    You extract 3D printing model metadata from the text of a model page. \
    Only output values that are literally supported by the page text; use null \
    whenever the text does not clearly state a value. Never guess or infer. \
    "supports" is "yes" or "no" only if the page clearly states whether support \
    structures are needed. "nozzle" and "layer_height" are millimeter values \
    like "0.4". "license" is the license named on the page. "tags" are up to 6 \
    short lowercase keywords describing the model, based on the page content; \
    use an empty array if unsure.
    """

    private func callClaude(
        apiKey: String,
        pageText: String,
        missingFields: [String],
        existingTags: [String]
    ) async throws -> [String: Any] {
        let userContent = """
        Fields to extract (leave all others null): \(missingFields.isEmpty ? "none — only suggest tags" : missingFields.joined(separator: ", "))
        Existing tags (do not repeat): \(existingTags.isEmpty ? "none" : existingTags.joined(separator: ", "))

        Page text:
        \(pageText)
        """

        let body: [String: Any] = [
            "model": Self.claudeModel,
            "max_tokens": 1024,
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": userContent]],
            "output_config": ["format": ["type": "json_schema", "schema": Self.outputSchema]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIEnrichmentError.apiFailed(error.localizedDescription)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIEnrichmentError.apiFailed("invalid response")
        }
        if let error = json["error"] as? [String: Any] {
            throw AIEnrichmentError.apiFailed(error["message"] as? String ?? "unknown error")
        }
        guard let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw AIEnrichmentError.apiFailed("unexpected response format")
        }
        return parsed
    }
}
