import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ArchiveStore

    @State private var selectedTags: Set<String> = []
    @State private var selectedCollection: String?
    @State private var matchAll = false
    @State private var minRating = 0
    @State private var searchText = ""
    @State private var selectedModelID: Model3D.ID?
    @State private var showingNewModelSheet = false

    private var filteredModels: [Model3D] {
        store.models.filter { model in
            if let selectedCollection {
                guard model.collections.contains(selectedCollection) else { return false }
            }
            if minRating > 0 {
                guard model.rating >= minRating else { return false }
            }
            if !selectedTags.isEmpty {
                let modelTags = Set(model.tags)
                if matchAll {
                    guard selectedTags.isSubset(of: modelTags) else { return false }
                } else {
                    guard !selectedTags.isDisjoint(with: modelTags) else { return false }
                }
            }
            if !searchText.isEmpty {
                guard model.matches(search: searchText) else { return false }
            }
            return true
        }
    }

    var body: some View {
        Group {
            if store.rootURL == nil {
                WelcomeView()
            } else {
                NavigationSplitView {
                    SidebarView(
                        selectedTags: $selectedTags,
                        selectedCollection: $selectedCollection,
                        matchAll: $matchAll,
                        minRating: $minRating
                    )
                    .navigationSplitViewColumnWidth(min: 180, ideal: 230)
                } content: {
                    ModelBrowserView(
                        models: filteredModels,
                        selectedID: $selectedModelID,
                        onNewModel: { showingNewModelSheet = true }
                    )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 440)
                } detail: {
                    if let model = store.models.first(where: { $0.id == selectedModelID }) {
                        ModelDetailView(model: model)
                            .id(model.id)
                    } else {
                        ContentUnavailableView(
                            "Kein Modell ausgewählt",
                            systemImage: "cube.transparent",
                            description: Text("Wähle ein Modell aus oder lege mit + ein neues an.")
                        )
                    }
                }
                .searchable(text: $searchText, placement: .toolbar, prompt: "Titel, Tags, Beschreibung …")
            }
        }
        .sheet(isPresented: $showingNewModelSheet) {
            NewModelSheet { name in
                if let model = store.createModel(named: name) {
                    selectedModelID = model.id
                }
            }
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .frame(minWidth: 960, minHeight: 580)
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var store: ArchiveStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Willkommen bei 3Dark")
                .font(.largeTitle.bold())
            Text("Wähle den Ordner, in dem deine 3D-Modelle liegen sollen.\nJedes Modell bekommt darin einen eigenen Unterordner mit einer model.md.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Archiv-Ordner wählen …") {
                store.chooseRootFolder()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}
