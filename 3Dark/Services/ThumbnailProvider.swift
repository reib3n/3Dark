import AppKit
import ImageIO
import Metal
import SceneKit

/// Liefert Vorschaubilder: entweder ein vom Nutzer gewähltes Bild aus dem
/// Modellordner (Frontmatter `vorschaubild`) oder ein offscreen gerendertes
/// 3D-Thumbnail, das als `.thumbnail.png` im Modellordner abgelegt wird.
actor ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private var imageCache: [String: (modified: Date, image: NSImage)] = [:]

    func thumbnail(for model: Model3D) -> NSImage? {
        if let imageFile = model.previewImageFile,
           let image = loadImageThumbnail(imageFile) {
            return image
        }
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

    /// Herunterskalierte Bildvorschau, z. B. für Hover-Popover.
    func imagePreview(for url: URL) -> NSImage? {
        loadImageThumbnail(url)
    }

    /// Bilddatei als herunterskaliertes Thumbnail laden (mit Cache).
    private func loadImageThumbnail(_ url: URL) -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if let cached = imageCache[url.path], cached.modified == modified {
            return cached.image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: .zero)
        imageCache[url.path] = (modified, image)
        return image
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
