//
//  RangeShaper.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  A colour cube only reads `0…1`; anything brighter is clamped. To run a
//  cube over HDR values, each channel is first squeezed into `0…1` by a 1D
//  curve (`CIColorCurves`, extended domain), looked up, and stretched back.
//  The squeeze is exactly linear below white (×0.8), so SDR values lose
//  nothing to the shaper itself, and rolls the range above white —
//  measured up to 63 (display-encoded) — into the top fifth.
//

import CoreImage
import Foundation

/// Squeeze / stretch around a colour cube.
enum RangeShaper {

    /// Where encoded white lands in the squeezed range.
    static let knee = 0.8

    /// The largest encoded value carried (an encoded 63 is far beyond any
    /// HDR display); brighter clamps there.
    static let ceiling = 63.0

    /// Entries per 1D table. 4095 is a multiple of 5 and of 63, so white
    /// (and the knee) fall exactly on samples in both directions.
    static let entries = 4096

    /// The colour space the shaper and the cube agree on.
    static let space = CGColorSpace(name: CGColorSpace.extendedSRGB)!

    /// Encoded `v ≥ 0` → `0…1`.
    static func squeeze(_ v: Double) -> Double {
        if v <= 1 { return max(0, v) * knee }
        let over = min(v, ceiling) - 1
        return knee + (1 - knee) * over / (over + 2)
    }

    /// `0…1` → encoded value (the inverse of ``squeeze(_:)``).
    static func stretch(_ u: Double) -> Double {
        if u <= knee { return max(0, u) / knee }
        let s = min((u - knee) / (1 - knee), 0.999_999)
        return 1 + 2 * s / (1 - s)
    }

    /// `image` through a cube built over squeezed values.
    static func apply(cube: Data, dimension: Int, to image: CIImage) -> CIImage {
        image
            .applyingFilter("CIColorCurves", parameters: [
                "inputCurvesData": table(squeeze, upTo: ceiling),
                "inputCurvesDomain": CIVector(x: 0, y: CGFloat(ceiling)),
                "inputColorSpace": space,
            ])
            .applyingFilter("CIColorCubeWithColorSpace", parameters: [
                "inputCubeDimension": dimension,
                "inputCubeData": cube,
                "inputColorSpace": space,
            ])
            .applyingFilter("CIColorCurves", parameters: [
                "inputCurvesData": table(stretch, upTo: 1),
                "inputCurvesDomain": CIVector(x: 0, y: 1),
                "inputColorSpace": space,
            ])
            .cropped(to: image.extent)
    }

    /// A `CIColorCurves` table of `f` over `0…upper`, the same for R, G, B.
    static func table(_ f: (Double) -> Double, upTo upper: Double) -> Data {
        var values = [Float]()
        values.reserveCapacity(entries * 3)
        for i in 0..<entries {
            let y = Float(f(upper * Double(i) / Double(entries - 1)))
            values.append(y); values.append(y); values.append(y)
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
