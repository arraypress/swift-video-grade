//
//  SkinSmoothFilter.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import CoreImage
import Foundation
import Vision

/// Skin-only smoothing: softens skin without plasticizing the whole frame.
///
/// Apple has no first-party skin-smooth API, so this composes one from
/// parts it does ship: Vision face detection bounds the effect to faces, a
/// skin-tone color cube (YCbCr skin range) confines it to actual skin —
/// eyes, brows, lips, and hair stay sharp — and a feathered blur blend does
/// the softening. Runs identically in preview and export.
public final class SkinSmoothFilter: @unchecked Sendable {

    private let request: VNDetectFaceRectanglesRequest
    private let lock = NSLock()

    /// Smoothing intensity `0…1`.
    public var intensity: Double

    public init(intensity: Double) {
        self.intensity = intensity
        request = VNDetectFaceRectanglesRequest()
    }

    /// A 32-point color cube that outputs white for skin-like colors
    /// (classic YCbCr skin segmentation, softened at the edges).
    private static let skinCube: Data = {
        let dimension = 32
        var values = [Float](repeating: 0, count: dimension * dimension * dimension * 4)
        var index = 0
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let rf = Double(r) / Double(dimension - 1) * 255
                    let gf = Double(g) / Double(dimension - 1) * 255
                    let bf = Double(b) / Double(dimension - 1) * 255
                    let cb = 128 - 0.168736 * rf - 0.331264 * gf + 0.5 * bf
                    let cr = 128 + 0.5 * rf - 0.418688 * gf - 0.081312 * bf
                    // Soft membership inside the classic skin window.
                    let cbScore = softWindow(cb, low: 77, high: 127, feather: 10)
                    let crScore = softWindow(cr, low: 133, high: 173, feather: 10)
                    let score = Float(cbScore * crScore)
                    values[index] = score
                    values[index + 1] = score
                    values[index + 2] = score
                    values[index + 3] = 1
                    index += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }()

    private static func softWindow(_ value: Double, low: Double, high: Double, feather: Double) -> Double {
        if value < low - feather || value > high + feather { return 0 }
        if value >= low && value <= high { return 1 }
        let edge = value < low ? (value - (low - feather)) / feather : ((high + feather) - value) / feather
        return max(0, min(1, edge))
    }

    public func apply(_ image: CIImage) -> CIImage {
        guard intensity > 0.02 else { return image }

        lock.lock()
        defer { lock.unlock() }

        // 1. Find faces.
        let handler = VNImageRequestHandler(ciImage: image)
        guard (try? handler.perform([request])) != nil,
              let faces = request.results, !faces.isEmpty else {
            return image
        }

        // 2. Feathered ellipse mask around each face (slightly expanded).
        let extent = image.extent
        var faceMask = CIImage(color: .black).cropped(to: extent)
        for face in faces {
            let rect = CGRect(
                x: extent.minX + face.boundingBox.minX * extent.width,
                y: extent.minY + face.boundingBox.minY * extent.height,
                width: face.boundingBox.width * extent.width,
                height: face.boundingBox.height * extent.height
            )
            let radius = max(rect.width, rect.height) * 0.72
            let radial = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: rect.midX, y: rect.midY),
                "inputRadius0": radius * 0.62,
                "inputRadius1": radius * 1.05,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black,
            ])?.outputImage?.cropped(to: extent) ?? faceMask
            faceMask = radial.applyingFilter("CIMaximumCompositing", parameters: [
                "inputBackgroundImage": faceMask,
            ])
        }

        // 3. Skin-tone mask from the image itself, intersected with faces,
        //    scaled by intensity.
        let skinMask = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": 32,
            "inputCubeData": Self.skinCube,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!,
        ])
        var mask = skinMask.applyingFilter("CIMultiplyCompositing", parameters: [
            "inputBackgroundImage": faceMask,
        ])
        let strength = CGFloat(min(1, intensity))
        mask = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0),
        ])

        // 4. Soft blur, blended in only where the mask allows.
        let radius = (3 + 7 * intensity) * extent.height / 1920
        let softened = image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
            .cropped(to: extent)

        return softened.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": image,
            "inputMaskImage": mask,
        ]).cropped(to: extent)
    }
}
