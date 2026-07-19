import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil = follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case german = "de"
    case english = "en"

    /// Default derived from the system language on first launch.
    static var initialValue: AppLanguage {
        Locale.current.language.languageCode?.identifier == "de" ? .german : .english
    }

    /// Always displayed in the language itself.
    var label: String {
        switch self {
        case .german: return "Deutsch"
        case .english: return "English"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

struct SettingsView: View {
    @AppStorage("AppearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("AppLanguage") private var languageRaw = AppLanguage.initialValue.rawValue

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 460)
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
        .environment(\.locale, (AppLanguage(rawValue: languageRaw) ?? .initialValue).locale)
    }

    private var generalTab: some View {
        Form {
            Section {
                Picker("Appearance:", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("“System” automatically follows the macOS setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Language:", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Text("Applies to the app’s interface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// AI enrichment settings: the Anthropic API key lives in the keychain
/// and is never displayed back.
private struct AISettingsTab: View {
    @State private var keyDraft = ""
    @State private var hasStoredKey = false

    var body: some View {
        Form {
            Section {
                SecureField("Anthropic API Key:", text: $keyDraft, prompt: Text(verbatim: "sk-ant-…"))
                HStack {
                    Button("Save Key") {
                        KeychainStore.set(keyDraft.trimmingCharacters(in: .whitespaces), for: AIEnrichmentService.apiKeyAccount)
                        keyDraft = ""
                        hasStoredKey = AIEnrichmentService.hasAPIKey
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove Key") {
                        KeychainStore.set(nil, for: AIEnrichmentService.apiKeyAccount)
                        keyDraft = ""
                        hasStoredKey = false
                    }
                    .disabled(!hasStoredKey)
                    Spacer()
                    Label(
                        hasStoredKey ? "A key is stored in your keychain." : "No key stored.",
                        systemImage: hasStoredKey ? "checkmark.circle" : "circle"
                    )
                    .font(.caption)
                    .foregroundStyle(hasStoredKey ? Color.green : Color.secondary)
                }
            }

            Section {
                Text("Enrichment loads the model’s source page and sends its text to the Claude API to fill missing fields. Your 3D files never leave your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasStoredKey = AIEnrichmentService.hasAPIKey
        }
    }
}
