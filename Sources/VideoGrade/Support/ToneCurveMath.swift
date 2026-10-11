//
//  ToneCurveMath.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  Lightroom's tone curve on display-encoded values, after LightCraft's
//  `curve_luts`: the parametric region curve (a raised-cosine window per
//  region, kept monotone), then the master point curve, then each
//  channel's point curve. Outside `0…1` the curve continues with slope 1
//  from its end values, so HDR values above white are carried, not cut.
//

import Foundation

/// Tone-curve evaluation.
enum ToneCurveMath {

    /// Samples per channel table.
    static let samples = 1024

    /// Whether the curve changes nothing.
    static func isIdentity(_ curve: ToneCurve) -> Bool {
        curve.shadows == 0 && curve.darks == 0 && curve.lights == 0 && curve.highlights == 0
            && MonotoneCurve.isIdentity(curve.master) && MonotoneCurve.isIdentity(curve.red)
            && MonotoneCurve.isIdentity(curve.green) && MonotoneCurve.isIdentity(curve.blue)
    }

    /// Red, green and blue tables over `0…1`, or `nil` for the identity.
    static func tables(_ curve: ToneCurve) -> [[Double]]? {
        guard !isIdentity(curve) else { return nil }
        let n = samples
        let s1 = clamp(curve.shadowSplit, 0.05, 0.9)
        let s2 = clamp(curve.midtoneSplit, s1 + 0.01, 0.95)
        let s3 = clamp(curve.highlightSplit, s2 + 0.01, 0.98)
        let regions: [(Double, Double, Double)] = [
            (0, s1, curve.shadows), (s1, s2, curve.darks), (s2, s3, curve.lights), (s3, 1, curve.highlights),
        ]
        var base = (0..<n).map { i -> Double in
            let x = Double(i) / Double(n - 1)
            var d = 0.0
            for (a, b, amount) in regions where amount != 0 {
                let centre = (a + b) / 2, half = (b - a) * 0.75 + 0.05
                let t = clamp((x - centre) / half, -1, 1)
                d += clamp(amount, -1, 1) * 0.22 * (0.5 + 0.5 * cos(t * .pi))
            }
            return clamp(x + d * 4 * x * (1 - x), 0, 1)
        }
        for i in 1..<n { base[i] = max(base[i], base[i - 1]) }
        if !MonotoneCurve.isIdentity(curve.master), let master = curve.master {
            let m = MonotoneCurve(master)
            base = base.map(m.eval)
        }
        return [curve.red, curve.green, curve.blue].map { points in
            guard !MonotoneCurve.isIdentity(points), let points else { return base }
            let c = MonotoneCurve(points)
            return base.map(c.eval)
        }
    }

    /// One channel's table at `v`: linear between samples, slope-1
    /// continuation outside `0…1`.
    static func eval(_ table: [Double], _ v: Double) -> Double {
        let n = table.count
        if v <= 0 { return table[0] + v }
        if v >= 1 { return table[n - 1] + (v - 1) }
        let f = v * Double(n - 1)
        let i = min(Int(f), n - 2)
        let t = f - Double(i)
        return table[i] + (table[i + 1] - table[i]) * t
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
}
