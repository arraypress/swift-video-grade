//
//  DetailBands.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  Texture (fine detail) and negative clarity. LightCraft scales a band in
//  log luminance; Core Image has no log, so this is the unsharp-mask
//  equivalent at LightCraft's radius: the texture band is detail finer
//  than 0.18 % of the long edge (at least 0.6 px). A negative unsharp mask
//  is a no-op in Core Image (measured), so smoothing blends toward the blur.
//

import CoreImage
import Foundation

/// Spatial detail controls.
enum DetailBands {

    /// Lightroom Texture, `-1…1`.
    static func texture(_ image: CIImage, amount: Double) -> CIImage {
        let extent = image.extent
        let radius = max(0.6, 0.0018 * max(extent.width, extent.height))
        return band(image, amount: min(1, max(-1, amount)) * 1.1, radius: radius, smoothing: 0.8)
    }

    /// Negative clarity, `-1…0`: midtone contrast softened at the radius
    /// positive clarity sharpens at.
    static func softenClarity(_ image: CIImage, amount: Double) -> CIImage {
        band(image, amount: max(-1, min(0, amount)), radius: 15, smoothing: 0.6)
    }

    /// Detail at `radius` scaled by `1 + amount` (positive) or blended
    /// toward its blur by `-amount·smoothing` (negative).
    private static func band(_ image: CIImage, amount: Double, radius: Double, smoothing: Double) -> CIImage {
        let extent = image.extent
        guard amount != 0, !extent.isEmpty, !extent.isInfinite else { return image }
        if amount > 0 {
            return image.clampedToExtent()
                .applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: radius, kCIInputIntensityKey: amount])
                .cropped(to: extent)
        }
        let blurred = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: blurred, kCIInputTimeKey: min(1, -amount * smoothing),
        ]).cropped(to: extent)
    }
}
