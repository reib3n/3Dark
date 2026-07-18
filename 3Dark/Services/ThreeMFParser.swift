import Foundation
import SceneKit
import SceneKit.ModelIO
import ModelIO

enum ThreeMFError: LocalizedError {
    case unzipFailed
    case noModelFound
    case invalidMesh

    var errorDescription: String? {
        switch self {
        case .unzipFailed: return "Die 3MF-Datei konnte nicht entpackt werden."
        case .noModelFound: return "Die 3MF-Datei enthält keine Modelldaten."
        case .invalidMesh: return "Die 3MF-Datei enthält kein gültiges Mesh."
        }
    }
}

/// Minimaler 3MF-Loader: entpackt das ZIP-Archiv und liest die Meshes
/// aus der enthaltenen .model-XML.
///
/// Einschränkung (MVP): Transformationen aus <build>-Items werden ignoriert,
/// alle Objekte werden am Ursprung zusammengeführt.
enum ThreeMFParser {
    static func loadGeometry(from url: URL) throws -> SCNGeometry {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("3Dark-3mf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-q", url.path, "-d", tempDir.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        // Exit-Code 1 = Warnungen, Inhalt wurde trotzdem entpackt.
        guard unzip.terminationStatus <= 1 else { throw ThreeMFError.unzipFailed }

        var modelFile: URL?
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.pathExtension.lowercased() == "model" {
                modelFile = candidate
                break
            }
        }
        guard let modelFile else { throw ThreeMFError.noModelFound }

        let parser = MeshXMLParser()
        guard parser.parse(data: try Data(contentsOf: modelFile)),
              !parser.vertices.isEmpty,
              !parser.indices.isEmpty else {
            throw ThreeMFError.invalidMesh
        }

        let source = SCNGeometrySource(vertices: parser.vertices)
        let element = SCNGeometryElement(indices: parser.indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])

        // 3MF enthält keine Normalen – über ModelIO erzeugen.
        let mesh = MDLMesh(scnGeometry: geometry)
        mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.8)
        return SCNGeometry(mdlMesh: mesh)
    }
}

private final class MeshXMLParser: NSObject, XMLParserDelegate {
    var vertices: [SCNVector3] = []
    var indices: [Int32] = []
    private var currentMeshBase = 0

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "mesh":
            currentMeshBase = vertices.count
        case "vertex":
            if let x = Double(attributeDict["x"] ?? ""),
               let y = Double(attributeDict["y"] ?? ""),
               let z = Double(attributeDict["z"] ?? "") {
                vertices.append(SCNVector3(x, y, z))
            }
        case "triangle":
            if let v1 = Int(attributeDict["v1"] ?? ""),
               let v2 = Int(attributeDict["v2"] ?? ""),
               let v3 = Int(attributeDict["v3"] ?? "") {
                indices.append(Int32(currentMeshBase + v1))
                indices.append(Int32(currentMeshBase + v2))
                indices.append(Int32(currentMeshBase + v3))
            }
        default:
            break
        }
    }
}
