//
//  DevelopTone.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  Lightroom's Whites and Blacks for display-referred images, after
//  LightCraft's `ToneMap::display`: in a gamma-2.2 perceptual domain,
//  Whites lifts or lowers the upper tones and Blacks the lower ones,
//  applied to luminance so colour ratios are kept. Unlike LightCraft there
//  is no shoulder at white: values above 1 continue, shifted, so HDR
//  highlights are carried rather than rolled off.
//

import Foundation

/// Whites / blacks on linear sRGB.
enum DevelopTone {

    /// `rgb` (linear) with `whites` and `blacks` (`-1…1`) applied.
    static func whitesBlacks(_ r: Double, _ g: Double, _ b: Double,
                             whites: Double, blacks: Double) -> (Double, Double, Double) {
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard y > 1e-7, whites != 0 || blacks != 0 else { return (r, g, b) }
        var p = pow(y, 1 / 2.2)
        if p <= 1 {
            p += whites * 0.12 * OkLab.smooth(0.45, 1, p) * (1 - p * 0.5)
            let low = 1 - OkLab.smooth(0, 0.45, p)
            p += blacks * 0.07 * low * min(p * 2, 1)
        } else {
            p += whites * 0.06
        }
        let o = pow(max(p, 0), 2.2)
        let k = o / y
        return (r * k, g * k, b * k)
    }
}
