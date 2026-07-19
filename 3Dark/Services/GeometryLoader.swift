import Foundation
import SceneKit
import SceneKit.ModelIO
import ModelIO

enum GeometryError: LocalizedError {
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let name):
            return String(localized: "\(name) could not be loaded.")
        }
    }
}

/// Loads 3D files and builds a display-ready scene from them
/// (centered, normalized, with material, camera, and lights).
enum GeometryLoader {
    /// Edge length the model is normalized to within the scene.
    private static let normalizedExtent: CGFloat = 10

    static func loadScene(from url: URL) throws -> SCNScene {
        makeScene(around: try loadModelNode(from: url))
    }

    /// Combined view: all parts true to scale next to each other on a
    /// shared ground plane (assuming identical units).
    static func loadCombinedScene(from urls: [URL]) throws -> SCNScene {
        var containers: [SCNNode] = []
        for url in urls {
            guard let node = try? loadModelNode(from: url) else { continue }
            let container = SCNNode()
            container.addChildNode(node)
            containers.append(container)
        }
        guard !containers.isEmpty else {
            throw GeometryError.loadFailed("Combined view")
        }

        let boxes = containers.map { $0.boundingBox }
        let maxDimension = boxes
            .map { max($0.max.x - $0.min.x, max($0.max.y - $0.min.y, $0.max.z - $0.min.z)) }
            .max() ?? 1
        let gap = maxDimension * 0.15

        let group = SCNNode()
        var cursorX: CGFloat = 0
        for (container, box) in zip(containers, boxes) {
            container.position = SCNVector3(
                cursorX - box.min.x,
                -box.min.y,
                -(box.min.z + box.max.z) / 2
            )
            cursorX += (box.max.x - box.min.x) + gap
            group.addChildNode(container)
        }
        return makeScene(around: group)
    }

    private static func loadModelNode(from url: URL) throws -> SCNNode {
        let ext = url.pathExtension.lowercased()
        let modelNode: SCNNode

        if ext == "3mf" {
            modelNode = SCNNode(geometry: try ThreeMFParser.loadGeometry(from: url))
        } else if ext == "step" || ext == "stp" {
            modelNode = SCNNode(geometry: try STEPPointCloud.geometry(from: url))
        } else {
            let asset = MDLAsset(url: url)
            guard asset.count > 0 else {
                throw GeometryError.loadFailed(url.lastPathComponent)
            }
            let imported = SCNScene(mdlAsset: asset)
            modelNode = SCNNode()
            for child in imported.rootNode.childNodes {
                modelNode.addChildNode(child)
            }
        }

        // STL/3MF/PLY/STEP from the printing/CAD world are Z-up,
        // SceneKit is Y-up.
        if ["stl", "3mf", "ply", "step", "stp"].contains(ext) {
            modelNode.eulerAngles.x = -.pi / 2
        }

        // Point clouds keep their own constant-lit material.
        if ext != "step", ext != "stp" {
            applyPrintMaterial(to: modelNode)
        }
        return modelNode
    }

    private static func makeScene(around modelNode: SCNNode) -> SCNScene {
        let scene = SCNScene()

        let (minVec, maxVec) = modelNode.boundingBox
        let center = SCNVector3(
            (minVec.x + maxVec.x) / 2,
            (minVec.y + maxVec.y) / 2,
            (minVec.z + maxVec.z) / 2
        )
        let extent = max(maxVec.x - minVec.x, max(maxVec.y - minVec.y, maxVec.z - minVec.z))
        let scale = extent > 0 ? normalizedExtent / extent : 1
        modelNode.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
        modelNode.scale = SCNVector3(scale, scale, scale)
        modelNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(modelNode)

        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 200
        cameraNode.position = SCNVector3(9, 7, 14)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 900
        keyLight.eulerAngles = SCNVector3(-CGFloat.pi / 3, CGFloat.pi / 5, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 350
        fillLight.eulerAngles = SCNVector3(-CGFloat.pi / 6, CGFloat.pi, 0)
        scene.rootNode.addChildNode(fillLight)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        scene.rootNode.addChildNode(ambient)

        return scene
    }

    /// Uniform, material-neutral appearance for all models.
    private static func applyPrintMaterial(to node: SCNNode) {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(calibratedRed: 0.92, green: 0.56, blue: 0.18, alpha: 1)
        material.roughness.contents = 0.55
        material.metalness.contents = 0.05
        node.enumerateHierarchy { child, _ in
            child.geometry?.materials = [material]
        }
    }
}
