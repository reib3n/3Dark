import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ArchiveStore

    @State private var selectedTags: Set<String> = []
    @State private var selectedCollection: String?
    @State private var matchAll = false
    @State private var minRating = 0
    @State private var noSourceOnly = false
    @State private var searchText = ""
    @State private var selectedModelID: Model3D.ID?
    @State private var showingNewModelSheet = false
    @State private var showingTrash = false
    @AppStorage("RecentFirst") private var recentFirst = true
    @AppStorage("RecentMode") private var recentModeRaw = "days"
    @AppStorage("RecentValue") private var recentValue = 14

    private var recentIDs: Set<Model3D.ID> {
        Model3D.recentIDs(in: store.models, mode: recentModeRaw, value: recentValue)
    }

    private var hasActiveFilters: Bool {
        selectedCollection != nil || minRating > 0 || noSourceOnly
            || !selectedTags.isEmpty || !searchText.isEmpty
    }

    private var displayedModels: [Model3D] {
        if showingTrash {
            return store.trashedModels.filter { searchText.isEmpty || $0.matches(search: searchText) }
        }
        let filtered = filteredModels
        // Default view: recently added on top (newest first), the rest
        // stays alphabetical. Any active filter restores plain order.
        guard recentFirst, !hasActiveFilters else { return filtered }
        let recents = recentIDs
        let newOnes = filtered
            .filter { recents.contains($0.id) }
            .sorted { ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast) }
        let rest = filtered.filter { !recents.contains($0.id) }
        return newOnes + rest
    }

    private var filteredModels: [Model3D] {
        store.models.filter { model in
            if let selectedCollection {
                guard model.collections.contains(selectedCollection) else { return false }
            }
            if minRating > 0 {
                guard model.rating >= minRating else { return false }
            }
            if noSourceOnly {
                guard model.frontmatter.string("source").isEmpty else { return false }
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
                        minRating: $minRating,
                        noSourceOnly: $noSourceOnly,
                        recentFirst: $recentFirst,
                        showingTrash: $showingTrash
                    )
                    .navigationSplitViewColumnWidth(min: 180, ideal: 230)
                } content: {
                    ModelBrowserView(
                        models: displayedModels,
                        selectedID: $selectedModelID,
                        isTrash: showingTrash,
                        recentIDs: showingTrash ? [] : recentIDs,
                        onNewModel: { showingNewModelSheet = true }
                    )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 440)
                } detail: {
                    if let model = (store.models + store.trashedModels).first(where: { $0.id == selectedModelID }) {
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
