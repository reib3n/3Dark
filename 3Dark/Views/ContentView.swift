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
                            "No Model Selected",
                            systemImage: "cube.transparent",
                            description: Text("Select a model or create a new one with +.")
                        )
                    }
                }
                .searchable(text: $searchText, placement: .toolbar, prompt: "Title, tags, description…")
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
            "Error",
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
            Text("Welcome to 3Dark")
                .font(.largeTitle.bold())
            Text("Choose the folder where your 3D models should live.\nEach model gets its own subfolder with a model.md.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Choose Archive Folder…") {
                store.chooseRootFolder()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}
