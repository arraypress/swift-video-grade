//
//  DevelopColor.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  Lightroom's colour mixer, black & white mix and colour grading in
//  OkLab / OkLCh, after LightCraft's `colorops` (MIT OR Apache-2.0): band
//  centres are the sRGB hues 0/30/60/120/180/225/270/315° measured in
//  OkLCh, neighbours share a raised-cosine partition of unity, and the
//  grading ranges are smoothsteps over OkLab lightness.
//

import Foundation

/// The colour stage of the develop cube, resolved once per grade.
struct DevelopColor {

    /// sRGB hue of each band centre, red first.
    static let bandSRGBHues: [Double] = [0, 30, 60, 120, 180, 225, 270, 315]

    /// OkLCh hue (radians) of each band centre.
    static let bandHues: [Double] = bandSRGBHues.map { OkLab.hue(ofSRGBHue: $0) }

    private let mixer: (hue: [Double], sat: [Double], lum: [Double])?
    private let mono: [Double]?
    private let wheels: [(a: Double, b: Double, lum: Double)]?
    private let blending: Double
    private let balance: Double

    init(grade: VideoGrade) {
        if let m = grade.colorMixer, !m.isIdentity {
            let bands = m.bands
            mixer = (bands.map { Self.clamp($0.hue) * 0.5 },
                     bands.map { Self.clamp($0.saturation) },
                     bands.map { Self.clamp($0.luminance) * 0.18 })
        } else {
            mixer = nil
        }
        mono = grade.monochromeMix.map { $0.bands.map(Self.clamp) }
        if let g = grade.colorGrading, !g.isIdentity {
            wheels = [g.shadows, g.midtones, g.highlights, g.global].map { w in
                let h = OkLab.hue(ofSRGBHue: w.hue)
                let s = min(1, max(0, w.saturation)) * 0.09
                return (s * cos(h), s * sin(h), Self.clamp(w.luminance) * 0.12)
            }
            blending = min(1, max(0, g.blending))
            balance = Self.clamp(g.balance)
        } else {
            wheels = nil
            blending = 0.5
            balance = 0
        }
    }

    /// Whether this stage changes anything.
    var isActive: Bool { mixer != nil || mono != nil || wheels != nil }

    /// Partition-of-unity weights of OkLCh hue `h` over the eight bands.
    static func bandWeights(_ h: Double) -> [Double] {
        var w = [Double](repeating: 0, count: 8)
        let twoPi = 2 * Double.pi
        for i in 0..<8 {
            let a = bandHues[i], b = bandHues[(i + 1) % 8]
            var span = OkLab.wrap(b - a)
            if span < 0 { span += twoPi }
            var d = OkLab.wrap(h - a)
            if d < 0 { d += twoPi }
            if d <= span {
                let t = d / span
                let s = 0.5 - 0.5 * cos(t * .pi)
                w[i] += 1 - s
                w[(i + 1) % 8] += s
                break
            }
        }
        return w
    }

    /// Applies the mixer, the black & white mix and the grading to a
    /// linear sRGB colour.
    func apply(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        var lab = OkLab.fromLinear(r, g, b)
        if mixer != nil || mono != nil {
            var (l, c, h) = OkLab.lch(lab.0, lab.1, lab.2)
            if let mixer {
                let w = Self.bandWeights(h)
                var dh = 0.0, ds = 0.0, dl = 0.0
                for i in 0..<8 {
                    dh += w[i] * mixer.hue[i]
                    ds += w[i] * mixer.sat[i]
                    dl += w[i] * mixer.lum[i]
                }
                let chromaWeight = min(c / 0.12, 1)
                h += dh * chromaWeight
                c *= max(0, 1 + ds)
                l += dl * chromaWeight * max(l, 0.05).squareRoot()
            }
            if let mono {
                let w = Self.bandWeights(h)
                let mix = (0..<8).reduce(0.0) { $0 + w[$1] * mono[$1] }
                l = max(0, l + mix * min(c / 0.2, 1) * 0.25)
                c = 0
            }
            lab = OkLab.lab(l, c, h)
        }
        if let wheels {
            let m = 0.5 - balance * 0.25
            let width = 0.15 + blending * 0.5
            let ws = 1 - OkLab.smooth(m - width, m + width * 0.25, lab.0)
            let wh = OkLab.smooth(m - width * 0.25, m + width, lab.0)
            let wm = max(0, 1 - ws - wh)
            for (k, weight) in zip(wheels, [ws, wm, wh, 1]) {
                lab.1 += k.a * weight
                lab.2 += k.b * weight
                lab.0 += k.lum * weight
            }
        }
        return OkLab.toLinear(lab.0, lab.1, lab.2)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }
}
