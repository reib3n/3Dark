import Foundation
import SceneKit

/// Bounding-box size of a model in millimeters.
struct ModelDimensions: Equatable {
    var x: Double
    var y: Double
    var z: Double

    /// Front matter representation, e.g. `20.0 x 20.0 x 15.0`.
    var frontmatterValue: String {
        String(format: "%.1f x %.1f x %.1f", x, y, z)
    }

    var displayValue: String {
        String(format: "%.1f × %.1f × %.1f mm", x, y, z)
    }

    static func parse(_ raw: String) -> ModelDimensions? {
        let parts = raw.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "mm", with: "")
            .split(separator: "x")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        guard parts.count == 3 else { return nil }
        return ModelDimensions(x: parts[0], y: parts[1], z: parts[2])
    }

    /// Whether the part fits the given build volume, allowing the model
    /// to be rotated onto any axis (sorted comparison).
    func fits(bed: ModelDimensions) -> Bool {
        let part = [x, y, z].sorted()
        let volume = [bed.x, bed.y, bed.z].sorted()
        return zip(part, volume).allSatisfy { $0 <= $1 + 0.01 }
    }

    /// Whether it only fits when rotated — i.e. not in its current
    /// orientation, but in some other one.
    func needsRotation(bed: ModelDimensions) -> Bool {
        guard fits(bed: bed) else { return false }
        return !(x <= bed.x + 0.01 && y <= bed.y + 0.01 && z <= bed.z + 0.01)
    }
}

enum DimensionsReader {
    /// Measures a 3D file. STEP point clouds work too — the bounding box
    /// of the points is the part's extent.
    static func measure(fileURL: URL) -> ModelDimensions? {
        guard let node = try? GeometryLoader.loadRawNode(from: fileURL) else { return nil }
        let (minVec, maxVec) = node.boundingBox
        let dimensions = ModelDimensions(
            x: Double(maxVec.x - minVec.x),
            y: Double(maxVec.y - minVec.y),
            z: Double(maxVec.z - minVec.z)
        )
        guard dimensions.x > 0, dimensions.y > 0, dimensions.z > 0 else { return nil }
        return dimensions
    }
}
