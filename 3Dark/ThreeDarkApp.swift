import SwiftUI

@main
struct ThreeDarkApp: App {
    @StateObject private var store = ArchiveStore()
    @AppStorage("AppearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("AppLanguage") private var languageRaw = AppLanguage.german.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
                .environment(\.locale, (AppLanguage(rawValue: languageRaw) ?? .german).locale)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button("Archiv-Ordner wählen …") {
                    store.chooseRootFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}
