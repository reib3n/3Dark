import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    /// nil = der Systemeinstellung folgen.
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

    /// Anzeige immer in der jeweiligen Sprache selbst.
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
    @AppStorage("AppLanguage") private var languageRaw = AppLanguage.german.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Erscheinungsbild:", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("„System“ folgt automatisch der macOS-Einstellung.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Sprache:", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Text("Gilt für die Oberfläche der App.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
        .environment(\.locale, (AppLanguage(rawValue: languageRaw) ?? .german).locale)
    }
}
