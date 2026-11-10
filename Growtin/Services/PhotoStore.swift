import Foundation
import GrowtinCore
import ImageIO
import UIKit
import Vision

/// Stockage des photos de suivi, **uniquement sur l'appareil**.
/// Chaque fichier est écrit avec la protection `complete` : il est chiffré tant que l'iPhone est verrouillé.
@MainActor
final class PhotoStore {
    let directory: URL
    private let thumbnails = NSCache<NSString, UIImage>()

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
    }

    /// Dossier temporaire, utilisé par les aperçus et le mode démonstration.
    static func temporary() -> PhotoStore {
        PhotoStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("GrowtinDemoPhotos-\(UUID().uuidString)"))
    }

    func url(for fileName: String) -> URL { directory.appendingPathComponent(fileName) }

    func save(_ jpegData: Data, id: UUID) throws -> String {
        let fileName = "\(id.uuidString).jpg"
        try jpegData.write(to: url(for: fileName), options: [.atomic, .completeFileProtection])
        return fileName
    }

    func image(fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: fileName).path)
    }

    /// Miniature réduite sans charger l'image complète en mémoire.
    func thumbnail(fileName: String, maxPixelSize: Int = 360) -> UIImage? {
        let key = "\(fileName)-\(maxPixelSize)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url(for: fileName) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        thumbnails.setObject(image, forKey: key)
        return image
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
        thumbnails.removeAllObjects()
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        thumbnails.removeAllObjects()
    }
}

/// Préparation et analyse technique des photos. Aucune analyse ne porte sur l'état des cheveux.
enum PhotoAnalysis {
    /// Redessine l'image à l'endroit, réduite à `maxDimension`, et la réencode en JPEG.
    /// Le réencodage supprime aussi les métadonnées (dont une éventuelle position GPS).
    static func normalizedJPEG(from image: UIImage, maxDimension: CGFloat = 2048, mirrored: Bool = false) -> (data: Data, image: UIImage)? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
            if mirrored {
                context.cgContext.translateBy(x: target.width, y: 0)
                context.cgContext.scaleBy(x: -1, y: 1)
            }
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.85) else { return nil }
        return (data, rendered)
    }

    /// Image en niveaux de gris d'environ `targetWidth` pixels de large, pour l'analyse de qualité.
    static func grayImage(from cgImage: CGImage, targetWidth: Int = 512) -> GrayImage? {
        let width = min(targetWidth, cgImage.width)
        let height = max(3, Int(Double(cgImage.height) * Double(width) / Double(cgImage.width)))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? GrayImage(width: width, height: height, pixels: pixels) : nil
    }

    static func quality(of image: UIImage) -> ImageQuality? {
        guard let cgImage = image.cgImage, let gray = grayImage(from: cgImage) else { return nil }
        return ImageQualityAnalyzer.analyze(gray)
    }

    /// Position du visage le plus grand (coordonnées normalisées, origine en haut à gauche), via Vision.
    /// Sert uniquement à vérifier que le cadrage est similaire d'une photo à l'autre.
    static func faceFraming(in image: UIImage) async -> (centerX: Double, centerY: Double, width: Double)? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> (Double, Double, Double)? in
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { return nil }
            let box = face.boundingBox
            return (Double(box.midX), Double(1 - box.midY), Double(box.width))
        }.value
    }
}
