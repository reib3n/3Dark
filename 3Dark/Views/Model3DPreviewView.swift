import SwiftUI
import SceneKit

struct Model3DPreviewView: View {
    let url: URL?

    @State private var scene: SCNScene?
    @State private var errorText: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let scene {
                SceneView(scene: scene, options: [.allowsCameraControl])
            } else if isLoading {
                ProgressView()
            } else if let errorText {
                ContentUnavailableView(
                    "Vorschau nicht möglich",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorText)
                )
            } else {
                ContentUnavailableView(
                    "Keine 3D-Datei",
                    systemImage: "cube.transparent",
                    description: Text("Lege eine STL- oder 3MF-Datei in den Modellordner.")
                )
            }
        }
        .task(id: url) {
            scene = nil
            errorText = nil
            guard let url else { return }
            isLoading = true
            defer { isLoading = false }

            let result = await Task.detached(priority: .userInitiated) { () -> Result<SCNScene, Error> in
                do {
                    return .success(try GeometryLoader.loadScene(from: url))
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let loaded):
                scene = loaded
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }
}
