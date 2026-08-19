//
//  ColorGradeCube.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import CoreImage
import Foundation

/// Bakes the hue/tone-based grade stages — split tone, skin tone, and the
/// black-&-white hue mixer — into a single 3D color-cube LUT so they apply as
/// one cheap `CIColorCubeWithColorSpace` pass (no custom Metal, no metallib).
///
/// The per-hue math is re-authored from FilterSpark's `smoothTreatment`
/// kernel: each pixel goes RGB→HSV, its hue selects one of 8 bands, and a
/// `smoothstep` across the band lerps that band's `(hueShift, satMul, lumMul)`
/// vector — identity being `(0, 1, 1)`.
enum ColorGradeCube {

    static let dimension = 32

    /// 8 hue-band edges (normalized 0…1), computed from the exact hue of
    /// FilterSpark's `DMKBWPaletteHSLAdjustment` anchor colors: red 0,
    /// orange 0.0828, yellow 0.1667, green 0.3333, aqua 0.5, blue 0.6667,
    /// purple 0.7495, magenta 0.8333.
    private static let edges: [Double] = [0, 0.0828, 0.1667, 0.3333, 0.5, 0.6667, 0.7495, 0.8333]

    /// 12 evenly-spaced hue-band edges (n/12) for the full HSL tool.
    private static let edges12: [Double] = (0..<12).map { Double($0) / 12 }

    /// RGBA-float cube data for `grade`, or `nil` when no hue/tone stage is on.
    static func data(for grade: VideoGrade) -> Data? {
        let hasSplit = (grade.splitShadow != nil && grade.splitShadowAmount != 0)
            || (grade.splitHighlight != nil && grade.splitHighlightAmount != 0)
        let hasSkin = grade.skinTone != 0
        let hasBW = grade.blackAndWhite
        let hasCurves = isActive(grade.curveRGB) || isActive(grade.curveRed)
            || isActive(grade.curveGreen) || isActive(grade.curveBlue)
        let hslBands = grade.hslBands
        let hasHSL = (hslBands?.contains { !$0.isIdentity } ?? false) && hslBands?.count == 12
        let hslShifts: [(Double, Double, Double)] = hasHSL
            ? (hslBands ?? []).map { ($0.hue * 0.08, 1 + $0.sat, 1 + $0.lum) }
            : []
        let hasBrilliance = grade.brilliance != 0
        let hasDehaze = grade.dehaze != 0
        guard hasSplit || hasSkin || hasBW || hasCurves || hasHSL || hasBrilliance || hasDehaze else { return nil }

        // Split-tone per-channel curve endpoints.
        let sh = grade.splitShadow.map { ($0.red, $0.green, $0.blue) } ?? (0, 0, 0)
        let hl = grade.splitHighlight.map { ($0.red, $0.green, $0.blue) } ?? (0, 0, 0)
        let sA = grade.splitShadowAmount, hA = grade.splitHighlightAmount
        let shadowScale = (r: sh.0 * sA, g: sh.1 * sA, b: sh.2 * sA)
        // Highlight cross-mix: each channel = average of the OTHER two raw
        // highlight channels (FilterSpark's complementary tint trick).
        let hr = hl.0 * hA, hg = hl.1 * hA, hb = hl.2 * hA
        let highlightScale = (r: (hg + hb) / 2, g: (hr + hb) / 2, b: (hr + hg) / 2)

        // Per-hue luminance multipliers for the B&W mixer: identity 1 + band.
        let bwLum: [Double] = [
            grade.bwRed, grade.bwOrange, grade.bwYellow, grade.bwGreen,
            grade.bwAqua, grade.bwBlue, grade.bwPurple, grade.bwMagenta,
        ].map { 1 + $0 }
        let skinDelta = grade.skinTone / 24.30 // FilterSpark's active divisor

        let n = dimension
        var bytes = [Float](repeating: 0, count: n * n * n * 4)
        var index = 0
        for bi in 0..<n {
            let bIn = Double(bi) / Double(n - 1)
            for gi in 0..<n {
                let gIn = Double(gi) / Double(n - 1)
                for ri in 0..<n {
                    var r = Double(ri) / Double(n - 1), g = gIn, b = bIn

                    if hasCurves {
                        // Master curve on all channels, then per-channel.
                        r = evalCurve(r, grade.curveRGB); g = evalCurve(g, grade.curveRGB); b = evalCurve(b, grade.curveRGB)
                        r = evalCurve(r, grade.curveRed)
                        g = evalCurve(g, grade.curveGreen)
                        b = evalCurve(b, grade.curveBlue)
                    }
                    if hasSplit {
                        r = splitCurve(r, shadowScale.r, highlightScale.r)
                        g = splitCurve(g, shadowScale.g, highlightScale.g)
                        b = splitCurve(b, shadowScale.b, highlightScale.b)
                    }
                    if hasHSL {
                        (r, g, b) = huePass(r, g, b, shifts: hslShifts, edges: edges12)
                    }
                    if hasSkin, !hasBW {
                        // Shift only the red band's hue (warm/cool skin).
                        var shifts = Array(repeating: (0.0, 1.0, 1.0), count: 8)
                        shifts[0] = (skinDelta, 1.0, 1.0)
                        (r, g, b) = huePass(r, g, b, shifts: shifts)
                    }
                    if hasBrilliance {
                        (r, g, b) = brilliance(r, g, b, grade.brilliance)
                    }
                    if hasDehaze {
                        (r, g, b) = dehaze(r, g, b, grade.dehaze)
                    }
                    if hasBW {
                        // Re-weight each hue's luminance, then desaturate to a
                        // proper luma gray so red/orange brightening carries.
                        let shifts = bwLum.map { (0.0, 1.0, $0) }
                        let (mr, mg, mb) = huePass(r, g, b, shifts: shifts)
                        let luma = 0.299 * mr + 0.587 * mg + 0.114 * mb
                        r = luma; g = luma; b = luma
                    }

                    bytes[index] = Float(clamp01(r))
                    bytes[index + 1] = Float(clamp01(g))
                    bytes[index + 2] = Float(clamp01(b))
                    bytes[index + 3] = 1
                    index += 4
                }
            }
        }
        return bytes.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: - Math

    private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

    /// A curve counts as active only if it bends away from the identity line.
    /// Internal rather than private: ``VideoGrade/isNeutral`` answers with it.
    static func isActive(_ points: [CGPoint]?) -> Bool {
        guard let points, points.count >= 2 else { return false }
        return points.contains { abs($0.x - $0.y) > 0.001 }
    }

    /// Evaluates a piecewise-linear tone curve at `v` (identity if unset).
    private static func evalCurve(_ v: Double, _ points: [CGPoint]?) -> Double {
        guard let points, points.count >= 2 else { return v }
        let pts = points.sorted { $0.x < $1.x }
        if v <= Double(pts[0].x) { return clamp01(Double(pts[0].y)) }
        if v >= Double(pts[pts.count - 1].x) { return clamp01(Double(pts[pts.count - 1].y)) }
        for i in 0..<(pts.count - 1) where v < Double(pts[i + 1].x) {
            let x0 = Double(pts[i].x), x1 = Double(pts[i + 1].x)
            let y0 = Double(pts[i].y), y1 = Double(pts[i + 1].y)
            let t = (v - x0) / max(1e-6, x1 - x0)
            return clamp01(y0 + (y1 - y0) * t)
        }
        return clamp01(Double(pts[pts.count - 1].y))
    }

    /// A 5-point split-tone curve (fixed x positions 0/.25/.5/.75/1), lifting
    /// shadows and pulling highlights per FilterSpark's `mc_vectorForToneCurve`.
    private static func splitCurve(_ v: Double, _ shadow: Double, _ highlight: Double) -> Double {
        let x: [Double] = [0, 0.25, 0.5, 0.75, 1]
        let y: [Double] = [
            0 + 0.30 * shadow,
            0.25 + 0.15 * shadow,
            0.5,
            0.75 - 0.20 * highlight,
            1 - 0.40 * highlight,
        ]
        if v <= x[0] { return y[0] }
        if v >= x[4] { return y[4] }
        for i in 0..<4 where v < x[i + 1] {
            let t = (v - x[i]) / (x[i + 1] - x[i])
            return y[i] + (y[i + 1] - y[i]) * t
        }
        return y[4]
    }

    /// One RGB→(N-band hue treatment)→RGB pass over the given band edges.
    private static func huePass(
        _ r: Double, _ g: Double, _ b: Double,
        shifts: [(Double, Double, Double)],
        edges: [Double] = edges
    ) -> (Double, Double, Double) {
        guard shifts.count == edges.count, let last = edges.indices.last else { return (r, g, b) }
        var hsv = rgb2hsv(r, g, b)
        let h = hsv.0
        // Default to the wrap band (last → first), then find the real band.
        var e0 = edges[last], e1 = 1.0, s0 = shifts[last], s1 = shifts[0]
        for i in 0..<last where h < edges[i + 1] {
            e0 = edges[i]; e1 = edges[i + 1]; s0 = shifts[i]; s1 = shifts[i + 1]
            break
        }
        hsv = smoothTreatment(hsv, e0, e1, s0, s1)
        return hsv2rgb(hsv.0, hsv.1, hsv.2)
    }

    private static func smoothTreatment(
        _ hsv: (Double, Double, Double),
        _ edge0: Double, _ edge1: Double,
        _ shift0: (Double, Double, Double), _ shift1: (Double, Double, Double)
    ) -> (Double, Double, Double) {
        let t = smoothstep(edge0, edge1, hsv.0)
        let lumMul = shift0.2 + (shift1.2 - shift0.2) * t
        let hue = hsv.0 + (shift0.0 + (shift1.0 - shift0.0) * t)
        let sat = hsv.1 * (shift0.1 + (shift1.1 - shift0.1) * t)
        let lum = hsv.2 * lumMul
        var m = hsv.1
        if hsv.1 > 0.6 { m = hsv.1 * 1.2 }
        if m > 1 { m = 1 }
        return (hue, sat, hsv.2 + (lum - hsv.2) * m)
    }

    /// Exact port of FilterSpark's `brilliance` Metal kernel — a
    /// luminance-adaptive gain plus a saturation nudge. NOTE: the original adds
    /// `|intensity|·(1-s)·0.22` for BOTH signs (the negative branch's comment
    /// says "decrease" but the code adds), preserved here for parity.
    private static func brilliance(_ r: Double, _ g: Double, _ b: Double, _ intensity: Double) -> (Double, Double, Double) {
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        var rgb = (r, g, b)
        if intensity < 0 {
            let darkenFactor = 1 + intensity * (1 - luminance) * 1.1
            rgb = (r * darkenFactor, g * darkenFactor, b * darkenFactor)
        } else if luminance < 0.5 {
            let f = 1 + intensity * (1 - luminance)
            rgb = (r * f, g * f, b * f)
        } else {
            let smoothFactor = 1 + intensity * (1 - luminance) * 0.7
            rgb = (r * smoothFactor, g * smoothFactor, b * smoothFactor)
        }
        var hsv = rgb2hsv(rgb.0, rgb.1, rgb.2)
        if intensity > 0 {
            hsv.1 = clamp01(hsv.1 + intensity * (1 - hsv.1) * 0.22)
        } else if intensity < 0 {
            hsv.1 = clamp01(hsv.1 + abs(intensity) * (1 - hsv.1) * 0.22)
        }
        return hsv2rgb(hsv.0, hsv.1, hsv.2)
    }

    /// Exact port of FilterSpark's `dehaze` Metal kernel — a dark-channel-ish
    /// transmission divide, with a vibrance + contrast pass on the positive
    /// side. `atmosphericLight` is white (1,1,1), so `color - atmospheric`
    /// is `color - 1`.
    private static func dehaze(_ r: Double, _ g: Double, _ b: Double, _ intensity: Double) -> (Double, Double, Double) {
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        let transmission = 1 - luminance
        func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        if intensity > 0 {
            let adjusted = max(mix(1, transmission, intensity * 0.1), 0.2)
            var dr = (r - 1) / adjusted + 1
            var dg = (g - 1) / adjusted + 1
            var db = (b - 1) / adjusted + 1
            let vibrance = intensity * 0.3
            dr = mix(luminance, dr, 1 + vibrance)
            dg = mix(luminance, dg, 1 + vibrance)
            db = mix(luminance, db, 1 + vibrance)
            let contrast = 1 + intensity * 0.05
            return ((dr - 0.5) * contrast + 0.5, (dg - 0.5) * contrast + 0.5, (db - 0.5) * contrast + 0.5)
        } else {
            let adjusted = max(mix(1, transmission, intensity), 0.1)
            return ((r - 1) / adjusted + 1, (g - 1) / adjusted + 1, (b - 1) / adjusted + 1)
        }
    }

    private static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        guard e1 > e0 else { return x < e0 ? 0 : 1 }
        let t = clamp01((x - e0) / (e1 - e0))
        return t * t * (3 - 2 * t)
    }

    private static func rgb2hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let d = maxV - minV
        var h = 0.0
        if d > 1e-10 {
            if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if maxV == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
        }
        return (h, maxV <= 0 ? 0 : d / maxV, maxV)
    }

    private static func hsv2rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        if s <= 0 { return (v, v, v) }
        let hh = (h - floor(h)) * 6
        let i = Int(hh)
        let f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
