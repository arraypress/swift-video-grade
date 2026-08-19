//
//  CutRender.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import CoreImage
import Foundation

/// The CoreImage-based cut transitions (whip pan, zoom blur, glitch).
/// One `apply` shared by exporter and preview; `strength` is the boundary
/// envelope (`0` = no effect, `1` = boundary frame).
public enum CutRender {

    /// Whether a style needs the CoreImage pipeline (vs plain dip/punch).
    public static func needsCoreImage(_ style: CutStyle) -> Bool {
        switch style {
        case .whipPan, .zoomBlur, .glitch: return true
        case .none, .dipToBlack, .dipToWhite, .punchIn: return false
        }
    }

    /// Applies a boundary effect at `strength` (`0` = untouched, `1` = the
    /// boundary frame itself). Styles the pipeline does not handle — dip and
    /// punch — return the image unchanged; see ``needsCoreImage(_:)``.
    public static func apply(style: CutStyle, strength: Double, to image: CIImage) -> CIImage {
        guard strength > 0.01 else { return image }
        let extent = image.extent
        switch style {
        case .whipPan:
            return image
                .clampedToExtent()
                .applyingFilter("CIMotionBlur", parameters: [
                    "inputRadius": strength * 55,
                    "inputAngle": 0,
                ])
                .cropped(to: extent)
        case .zoomBlur:
            return image
                .clampedToExtent()
                .applyingFilter("CIZoomBlur", parameters: [
                    "inputCenter": CIVector(x: extent.midX, y: extent.midY),
                    "inputAmount": strength * 28,
                ])
                .cropped(to: extent)
        case .glitch:
            // Shift red left and blue right, keep green anchored.
            let shift = CGFloat(strength) * extent.width * 0.02
            let red = image
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                ])
                .transformed(by: CGAffineTransform(translationX: -shift, y: 0))
            let blue = image
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                ])
                .transformed(by: CGAffineTransform(translationX: shift, y: 0))
            let green = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ])
            // The three channels are disjoint, so per-channel MAX recombines
            // them exactly and keeps alpha at 1 — additive compositing would
            // sum the three alphas to 3 and wash out every downstream stage.
            return red
                .applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": green])
                .applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": blue])
                .cropped(to: extent)
        case .none, .dipToBlack, .dipToWhite, .punchIn:
            return image
        }
    }

    /// The boundary envelope: `1` at a boundary, fading over `window`.
    public static func strength(at time: TimeInterval, boundaries: [Double], window: Double = 0.16) -> Double {
        var strongest = 0.0
        for boundary in boundaries {
            strongest = max(strongest, 1 - abs(time - boundary) / window)
        }
        return max(0, min(1, strongest))
    }
}
