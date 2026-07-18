import Foundation
import SceneKit
import SceneKit.ModelIO
import ModelIO

enum GeometryError: LocalizedError {
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let name):
            return "\(name) konnte nicht geladen werden."
        }
    }
}

/// Lädt 3D-Dateien und baut daraus eine anzeigefertige Szene
/// (zentriert, normiert, mit Material, Kamera und Licht).
enum GeometryLoader {
    /// Kantenlänge, auf die das Modell in der Szene normiert wird.
    private static let normalizedExtent: CGFloat = 10

    static func loadScene(from url: URL) throws -> SCNScene {
        let ext = url.pathExtension.lowercased()
        let modelNode: SCNNode

        if ext == "3mf" {
            modelNode = SCNNode(geometry: try ThreeMFParser.loadGeometry(from: url))
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

        // STL/3MF/PLY aus der Druckerwelt sind Z-hoch, SceneKit ist Y-hoch.
        if ["stl", "3mf", "ply"].contains(ext) {
            modelNode.eulerAngles.x = -.pi / 2
        }

        applyPrintMaterial(to: modelNode)
        return makeScene(around: modelNode)
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

    /// Einheitliches, materialneutrales Erscheinungsbild für alle Modelle.
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
