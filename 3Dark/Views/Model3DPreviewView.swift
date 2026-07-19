import SwiftUI
import SceneKit

struct Model3DPreviewView: View {
    let files: [URL]
    @Binding var selectedFile: URL?

    @State private var scene: SCNScene?
    @State private var previewImage: NSImage?
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var resetToken = 0

    private enum PreviewContent {
        case scene(SCNScene)
        case image(NSImage)
    }

    private enum PreviewTarget: Equatable {
        case none
        case single(URL)
        case combined([URL])
    }

    private var target: PreviewTarget {
        if let selectedFile, files.contains(selectedFile) {
            return .single(selectedFile)
        }
        if files.count > 1 { return .combined(files) }
        if let first = files.first { return .single(first) }
        return .none
    }

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let scene {
                SceneKitView(scene: scene, resetToken: resetToken)
            } else if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            } else if isLoading {
                ProgressView()
            } else if let errorText {
                ContentUnavailableView(
                    "Preview Not Available",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorText)
                )
            } else {
                ContentUnavailableView(
                    "No 3D File",
                    systemImage: "cube.transparent",
                    description: Text("Place an STL or 3MF file in the model folder.")
                )
            }
        }
        .overlay(alignment: .topLeading) {
            switch target {
            case .combined(let urls):
                Text("Combined view · \(urls.count) parts")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassBackground(in: Capsule())
                    .padding(8)
            case .single(let url) where files.count > 1:
                Text(url.lastPathComponent)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassBackground(in: Capsule())
                    .padding(8)
            default:
                EmptyView()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if scene != nil {
                HStack(spacing: 8) {
                    if files.count > 1, selectedFile != nil {
                        Button {
                            selectedFile = nil
                        } label: {
                            Label("All Parts", systemImage: "square.grid.2x2")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .glassBackground(in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Show all parts together")
                    }
                    Button {
                        resetToken += 1
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .medium))
                            .padding(7)
                            .glassBackground(in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset view (center and rotate back)")
                }
                .padding(10)
            }
        }
        .task(id: target) {
            scene = nil
            previewImage = nil
            errorText = nil
            let target = target
            guard target != .none else { return }
            isLoading = true
            defer { isLoading = false }

            let result = await Task.detached(priority: .userInitiated) { () -> Result<PreviewContent, Error> in
                do {
                    switch target {
                    case .single(let url):
                        if url.pathExtension.lowercased() == "f3d" {
                            return .success(.image(try F3DPreview.extractImage(from: url)))
                        }
                        return .success(.scene(try GeometryLoader.loadScene(from: url)))
                    case .combined(let urls):
                        // F3D carries no loadable geometry — leave it out.
                        let meshURLs = urls.filter { $0.pathExtension.lowercased() != "f3d" }
                        return .success(.scene(try GeometryLoader.loadCombinedScene(from: meshURLs)))
                    case .none:
                        return .failure(GeometryError.loadFailed("Preview"))
                    }
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(.scene(let loaded)):
                scene = loaded
            case .success(.image(let image)):
                previewImage = image
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }
}

/// SCNView wrapper with camera reset.
///
/// Remembers the initial transform of the scene camera; on every new
/// `resetToken` the current camera (including the free cam SceneKit may
/// create on user interaction) is animated back to it.
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
