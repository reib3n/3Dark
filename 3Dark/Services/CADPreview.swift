import AppKit
import Foundation
import SceneKit

enum CADPreviewError: LocalizedError {
    case noPoints
    case notAnArchive
    case noEmbeddedImage

    var errorDescription: String? {
        switch self {
        case .noPoints:
            return String(localized: "The STEP file contains no readable geometry points.")
        case .notAnArchive:
            return String(localized: "The file is not a readable Fusion 360 archive.")
        case .noEmbeddedImage:
            return String(localized: "This Fusion 360 archive contains no embedded preview image.")
        }
    }
}

/// STEP is a BREP CAD format without meshes — faces cannot be rendered
/// without a CAD kernel. What *is* reliably extractable are the
/// CARTESIAN_POINT coordinates, which yield a recognizable point-cloud
/// silhouette of the part.
enum STEPPointCloud {
    static let maxPoints = 120_000

    static func geometry(from url: URL) throws -> SCNGeometry {
        let text = try String(contentsOf: url, encoding: .utf8)
        let points = points(fromText: text)
        guard !points.isEmpty else { throw CADPreviewError.noPoints }
        return geometry(fromPoints: points)
    }

    static func points(fromText text: String) -> [SCNVector3] {
        let regex = #/CARTESIAN_POINT\s*\(\s*'[^']*'\s*,\s*\(\s*([-+0-9.Ee]+)\s*,\s*([-+0-9.Ee]+)\s*,\s*([-+0-9.Ee]+)\s*\)\s*\)/#
        var points: [SCNVector3] = []
        for match in text.matches(of: regex) {
            guard let x = Double(match.1), let y = Double(match.2), let z = Double(match.3) else { continue }
            points.append(SCNVector3(x, y, z))
        }
        // Subsample very dense files evenly.
        if points.count > maxPoints {
            let step = points.count / maxPoints + 1
            points = stride(from: 0, to: points.count, by: step).map { points[$0] }
        }
        return points
    }

    static func geometry(fromPoints points: [SCNVector3]) -> SCNGeometry {
        let source = SCNGeometrySource(vertices: points)
        let element = SCNGeometryElement(
            indices: Array(0..<Int32(points.count)),
            primitiveType: .point
        )
        element.pointSize = 3
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 6
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor(calibratedRed: 0.92, green: 0.56, blue: 0.18, alpha: 1)
        geometry.materials = [material]
        return geometry
    }
}

/// Fusion 360 archives (.f3d) are ZIP containers that usually carry an
/// embedded preview image — the geometry itself is proprietary.
enum F3DPreview {
    static func extractImage(from url: URL) throws -> NSImage {
        // ZIP magic check before shelling out.
        guard let handle = try? FileHandle(forReadingFrom: url),
              let magic = try? handle.read(upToCount: 2),
              magic == Data([0x50, 0x4B]) else {
            throw CADPreviewError.notAnArchive
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("3Dark-f3d-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-q", url.path, "-d", tempDir.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus <= 1 else { throw CADPreviewError.notAnArchive }

        // Largest embedded image wins (thumbnails come in several sizes).
        var best: (url: URL, size: Int)?
        let imageExtensions = ["png", "jpg", "jpeg"]
        if let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let candidate as URL in enumerator {
                guard imageExtensions.contains(candidate.pathExtension.lowercased()) else { continue }
                let size = (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if best == nil || size > best!.size {
                    best = (candidate, size)
                }
            }
        }
        guard let best, let image = NSImage(contentsOf: best.url) else {
            throw CADPreviewError.noEmbeddedImage
        }
        return image
    }
}
