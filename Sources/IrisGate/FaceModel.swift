import Foundation
import CoreML
import Vision
import CoreImage
import CryptoKit
import IrisGateCore

enum IrisError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class FaceModel {
    let digest: String
    private let model: MLModel
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(url: URL) throws {
        // Identity includes all files and paths, not just a user-selected model name.
        var hasher = SHA256()
        let files: [URL]
        if url.hasDirectoryPath {
            guard let enumerator = FileManager.default.enumerator(at: url,
                includingPropertiesForKeys: [.isRegularFileKey]) else {
                throw IrisError.message("Cannot read model directory")
            }
            files = enumerator.compactMap { $0 as? URL }.filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.sorted { $0.path < $1.path }
        } else { files = [url] }
        for file in files {
            hasher.update(data: Data(file.path.replacingOccurrences(of: url.path, with: "").utf8))
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        }
        digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let compiled = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
        let config = MLModelConfiguration(); config.computeUnits = .all
        model = try MLModel(contentsOf: compiled, configuration: config)
        let inputs = model.modelDescription.inputDescriptionsByName
        guard inputs.count == 1, let input = inputs["input_image"], input.type == .image,
              input.imageConstraint?.pixelsWide == 112, input.imageConstraint?.pixelsHigh == 112,
              let output = model.modelDescription.outputDescriptionsByName["embedding"],
              output.type == .multiArray,
              output.multiArrayConstraint?.shape.reduce(1, { $0 * $1.intValue }) == 512 else {
            throw IrisError.message("Expected input_image (112×112 RGB) and embedding (512 floats).")
        }
    }

    func embedding(pixelBuffer: CVPixelBuffer, face: VNFaceObservation) throws -> [Float] {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let box = face.boundingBox
        let rect = CGRect(x: box.minX * image.extent.width, y: box.minY * image.extent.height,
                          width: box.width * image.extent.width, height: box.height * image.extent.height)
        // Eye alignment corrects roll. Output is an approximate crop; model-specific
        // five-landmark alignment and calibration remain necessary for production.
        var crop = image.cropped(to: rect).transformed(by:
            CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        if let left = face.landmarks?.leftEye, let right = face.landmarks?.rightEye,
           left.pointCount > 0, right.pointCount > 0 {
            func center(_ points: VNFaceLandmarkRegion2D) -> CGPoint {
                let pts = points.normalizedPoints
                return CGPoint(x: pts.reduce(0) { $0 + CGFloat($1.x) } / CGFloat(pts.count) * rect.width,
                               y: pts.reduce(0) { $0 + CGFloat($1.y) } / CGFloat(pts.count) * rect.height)
            }
            let a = center(left), b = center(right)
            var angle = atan2(b.y - a.y, b.x - a.x)
            if angle > .pi / 2 { angle -= .pi }; if angle < -.pi / 2 { angle += .pi }
            let transform = CGAffineTransform(translationX: -rect.width / 2, y: -rect.height / 2)
                .concatenating(CGAffineTransform(rotationAngle: -angle))
                .concatenating(CGAffineTransform(translationX: rect.width / 2, y: rect.height / 2))
            crop = crop.transformed(by: transform).cropped(to: CGRect(origin: .zero, size: rect.size))
        }
        crop = crop.transformed(by: CGAffineTransform(scaleX: 112 / rect.width, y: 112 / rect.height))
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 112, 112, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true,
             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { throw IrisError.message("Could not allocate model input") }
        context.render(crop, to: buffer)
        let input = try MLDictionaryFeatureProvider(dictionary: ["input_image": MLFeatureValue(pixelBuffer: buffer)])
        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: "embedding")?.multiArrayValue, array.count == 512,
              let normalized = Embeddings.normalize((0..<512).map { array[$0].floatValue }) else {
            throw IrisError.message("Model returned an invalid embedding")
        }
        return normalized
    }
}
