import SwiftUI
import SceneKit

struct Model3DPreviewView: View {
    let url: URL?

    @State private var scene: SCNScene?
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var resetToken = 0

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let scene {
                SceneKitView(scene: scene, resetToken: resetToken)
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
        .overlay(alignment: .bottomTrailing) {
            if scene != nil {
                Button {
                    resetToken += 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium))
                        .padding(7)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Ansicht zurücksetzen (zentrieren und zurückdrehen)")
                .padding(10)
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

/// SCNView-Einbettung mit Kamera-Reset.
///
/// Merkt sich die Ausgangs-Transformation der Szenenkamera; bei jedem neuen
/// `resetToken` wird die aktuelle Kamera (auch die Free-Cam, die SceneKit
/// bei Nutzerinteraktion anlegen kann) animiert dorthin zurückgesetzt.
private struct SceneKitView: NSViewRepresentable {
    let scene: SCNScene
    let resetToken: Int

    final class Coordinator {
        var initialTransform: SCNMatrix4?
        var cameraNode: SCNNode?
        var lastResetToken = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            view.scene = scene
            let camera = scene.rootNode.childNode(withName: "camera", recursively: false)
            view.pointOfView = camera
            context.coordinator.cameraNode = camera
            context.coordinator.initialTransform = camera?.transform
            context.coordinator.lastResetToken = resetToken
        }

        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            guard let initial = context.coordinator.initialTransform else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if let pointOfView = view.pointOfView, pointOfView !== context.coordinator.cameraNode {
                pointOfView.transform = initial
            }
            context.coordinator.cameraNode?.transform = initial
            if let camera = context.coordinator.cameraNode {
                view.pointOfView = camera
            }
            SCNTransaction.commit()
        }
    }
}
