//
//  HazeRemoval.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  Lightroom's Dehaze, after LightCraft (MIT OR Apache-2.0): the haze
//  model is I = J·t + A·(1 − t). The dark channel — each pixel's smallest
//  channel, blurred at 2 % of the long edge — estimates the veil; its
//  brightest value estimates the airlight A; the transmission is
//  t = max(1 − 0.95·amount·dark/A, 0.12) and J = (I − A·(1 − t)) / t.
//  Negative amounts add haze: I + (0.9·A − I)·k.
//
//  Built from Core Image primitives only. Division is the hard part — the
//  divide blend mode clamps to 0…1 (measured) — so J is written as
//  I·R(x) + A·S(x) with x = dark/A, and R and S are 1D curves. The whole
//  stage runs in linear light whatever the host's working space.
//

import CoreImage
import Foundation

/// Dark-channel-prior dehaze as a Core Image graph.
enum HazeRemoval {

    /// Where the maths happens.
    private static let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    /// `image` with `amount` (`-1…1`) of dehaze.
    static func apply(_ image: CIImage, amount: Double) -> CIImage {
        let amount = min(1, max(-1, amount))
        let extent = image.extent
        guard amount != 0, !extent.isEmpty, !extent.isInfinite,
              let lit = image.matchedFromWorkingSpace(to: linear) else { return image }

        // Opaque, unpremultiplied colour: CIColorMatrix unpremultiplies
        // before its matrix and premultiplies after (measured), so alpha
        // forced to 1 hands back each pixel's true colour.
        //
        // Every filter here that sets alpha from a bias also lights up the
        // transparent plane outside the image, making its extent infinite
        // — and clampedToExtent() of an infinite image does nothing — so
        // each one is cropped straight back (measured: uncropped, the edge
        // blur read black and the airlight plane read its clamp floor).
        let colour = lit.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: extent)
        let dark = darkChannel(of: colour, extent: extent)
        let maximum = dark.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
        let air = maximum
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0.05, y: 0.05, z: 0.05, w: 1),
                "inputMaxComponents": CIVector(x: RangeShaper.ceiling, y: RangeShaper.ceiling, z: RangeShaper.ceiling, w: 1),
            ])
            .cropped(to: maximum.extent)
        let airPlane = air.clampedToExtent().cropped(to: extent)
        // 1 / A, as squeeze then reciprocal-of-stretch: each table is
        // linear or smooth where it is sampled, so neither loses precision.
        let inverseAir = air
            .applyingFilter("CIColorCurves", parameters: [
                "inputCurvesData": RangeShaper.table(RangeShaper.squeeze, upTo: RangeShaper.ceiling),
                "inputCurvesDomain": CIVector(x: 0, y: CGFloat(RangeShaper.ceiling)),
            ])
            .applyingFilter("CIColorCurves", parameters: [
                "inputCurvesData": RangeShaper.table({ 1 / max(RangeShaper.stretch($0), 0.05) }, upTo: 1),
                "inputCurvesDomain": CIVector(x: 0, y: 1),
            ])
            .cropped(to: maximum.extent)
            .clampedToExtent()
        let x = dark
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: inverseAir])
            .cropped(to: extent)

        let (rCurve, sCurve) = curves(amount)
        let r = x.applyingFilter("CIColorCurves", parameters: [
            "inputCurvesData": RangeShaper.table(rCurve, upTo: 1), "inputCurvesDomain": CIVector(x: 0, y: 1),
        ])
        let s = x.applyingFilter("CIColorCurves", parameters: [
            "inputCurvesData": RangeShaper.table(sCurve, upTo: 1), "inputCurvesDomain": CIVector(x: 0, y: 1),
        ])
        // Opaque operands multiply and add component-wise: I·R + A·S, with
        // alpha summed to 2.
        let sum = s
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: airPlane])
            .applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: colour.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: r]),
            ])
        // Back to the source's alpha: multiply by a factor that is α in
        // colour and α/2 in alpha (premultiplied), i.e. (J·α, α).
        let restore = lit.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.5),
            "inputBiasVector": CIVector(x: 2, y: 2, z: 2, w: 0),
        ])
        let recovered = sum
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: restore])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1e6, y: 1e6, z: 1e6, w: 1),
            ])
            .cropped(to: extent)
        return recovered.matchedToWorkingSpace(from: linear) ?? image
    }

    /// Each pixel's smallest channel, blurred at 2 % of the long edge, as
    /// an opaque grey image.
    static func darkChannel(of image: CIImage, extent: CGRect) -> CIImage {
        func channel(_ v: CIVector) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": v, "inputGVector": v, "inputBVector": v,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).cropped(to: extent)
        }
        let minimum = channel(CIVector(x: 1, y: 0, z: 0, w: 0))
            .applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: channel(CIVector(x: 0, y: 1, z: 0, w: 0))])
            .applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: channel(CIVector(x: 0, y: 0, z: 1, w: 0))])
        let sigma = max(1, 0.02 * max(extent.width, extent.height))
        return minimum
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: sigma])
            .cropped(to: extent)
    }

    /// `R(x)` and `S(x)` so that the result is `I·R + A·S`, `x = dark / A`.
    static func curves(_ amount: Double) -> ((Double) -> Double, (Double) -> Double) {
        if amount > 0 {
            let t = { (x: Double) in max(1 - 0.95 * amount * min(1, max(0, x)), 0.12) }
            return ({ 1 / t($0) }, { 1 - 1 / t($0) })
        }
        let k = { (x: Double) in -amount * 0.7 * (0.35 + 0.65 * min(1, max(0, x))) }
        return ({ 1 - k($0) }, { 0.9 * k($0) })
    }
}
