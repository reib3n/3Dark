import SwiftUI

@main
struct ThreeDarkApp: App {
    @StateObject private var store = ArchiveStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
    }
}
