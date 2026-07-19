import SwiftUI

/// Batch AI enrichment: runs the single-model enrichment over every
/// model that has a source link and missing fields — with a preview,
/// progress, cancellation, and a result summary. Modal, so the archive
/// cannot be edited mid-run.
struct BatchEnrichmentView: View {
    @EnvironmentObject private var store: ArchiveStore
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case confirm
        case running
        case finished
    }

    private struct Summary {
        var enriched = 0
        var unchanged = 0
        var failures: [(model: String, reason: String)] = []
        var canceled = false
    }

    @State private var phase: Phase = .confirm
    @State private var candidates: [Model3D] = []
    @State private var currentIndex = 0
    @State private var currentName = ""
    @State private var summary = Summary()
    @State private var runTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("AI Enrichment", systemImage: "sparkles")
                .font(.headline)

            switch phase {
            case .confirm: confirmView
            case .running: runningView
            case .finished: finishedView
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            candidates = AIEnrichmentService.candidates(in: store.models)
        }
        .interactiveDismissDisabled(runTask != nil && phase == .running)
    }

    // MARK: - Phases

    @ViewBuilder
    private var confirmView: some View {
        if !AIEnrichmentService.hasAPIKey {
            Text("No API key set. Add one in Settings.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        } else if candidates.isEmpty {
            Text("Nothing to enrich — every model either has no source link or no missing fields.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            Text("\(candidates.count) models have a source link and missing fields. One request per model is sent to the Claude API.")
                .foregroundStyle(.secondary)
            Text("Models already checked by AI are skipped. Use the ✨ button on a single model to check it again.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(candidates) { model in
                        Label(model.title, systemImage: "cube")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start") { run() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(currentIndex), total: Double(candidates.count)) {
                Text("Enriching \(currentIndex) of \(candidates.count)…")
            } currentValueLabel: {
                Text(currentName)
                    .lineLimit(1)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    runTask?.cancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var finishedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.canceled {
                Text("Run canceled.")
                    .foregroundStyle(.secondary)
            }
            Label("Suggestions found for \(summary.enriched) models.", systemImage: "checkmark.circle")
                .foregroundStyle(summary.enriched > 0 ? Color.green : Color.secondary)
            if summary.unchanged > 0 {
                Label("No new suggestions: \(summary.unchanged)", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            if !summary.failures.isEmpty {
                Label("Failed: \(summary.failures.count)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(summary.failures, id: \.model) { failure in
                            Text(verbatim: "\(failure.model): \(failure.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Run loop

    private func run() {
        phase = .running
        runTask = Task {
            var result = Summary()
            for (index, model) in candidates.enumerated() {
                if Task.isCancelled {
                    result.canceled = true
                    break
                }
                currentIndex = index + 1
                currentName = model.title
                do {
                    let suggestions = try await AIEnrichmentService.shared.enrich(model: model)
                    if store.applyAISuggestions(suggestions, to: model) {
                        result.enriched += 1
                    } else {
                        result.unchanged += 1
                    }
                } catch let error as AIEnrichmentError {
                    result.failures.append((model.title, error.localizedDescription))
                    // Without a key every remaining request fails too.
                    if case .noAPIKey = error { break }
                } catch {
                    result.failures.append((model.title, error.localizedDescription))
                }
                // Gentle pacing between requests.
                try? await Task.sleep(for: .milliseconds(500))
            }
            summary = result
            phase = .finished
            runTask = nil
        }
    }
}
