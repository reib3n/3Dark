import AppKit
import Metal
import SceneKit

/// Rendert Thumbnails offscreen und legt sie als `.thumbnail.png`
/// im Modellordner ab (versteckt, jederzeit regenerierbar).
actor ThumbnailProvider {
    static let shared = ThumbnailProvider()

    func thumbnail(for model: Model3D) -> NSImage? {
        guard let sourceURL = model.primary3DFile else { return nil }
        let thumbnailURL = model.thumbnailURL

        if FileManager.default.fileExists(atPath: thumbnailURL.path),
           let thumbnailDate = try? thumbnailURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           let sourceDate = try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           thumbnailDate >= sourceDate,
           let image = NSImage(contentsOf: thumbnailURL) {
            return image
        }

        return render(source: sourceURL, to: thumbnailURL)
    }

    private func render(source: URL, to output: URL) -> NSImage? {
        guard let scene = try? GeometryLoader.loadScene(from: source) else { return nil }

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)

        let image = renderer.snapshot(
            atTime: 0,
            with: CGSize(width: 512, height: 512),
            antialiasingMode: .multisampling4X
        )

        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: output)
        }
        return image
    }
}
