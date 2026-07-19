import SwiftUI

@main
struct ThreeDarkApp: App {
    @StateObject private var store = ArchiveStore()
    @AppStorage("AppearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("AppLanguage") private var languageRaw = AppLanguage.initialValue.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
                .environment(\.locale, (AppLanguage(rawValue: languageRaw) ?? .initialValue).locale)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button("Choose Archive Folder…") {
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
