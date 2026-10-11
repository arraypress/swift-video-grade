//
//  MonotoneCurve.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  A monotone cubic Hermite spline (Fritsch–Carlson), after LightCraft's
//  `lightcraft_color::spline`. The points' outputs are first made
//  non-decreasing in x order, so no set of points can invert a tone; the
//  limiter then keeps the curve from overshooting between them.
//

import CoreGraphics
import Foundation

/// A tone curve through control points in `0…1`.
struct MonotoneCurve {

    private let xs: [Double]
    private let ys: [Double]
    private let ms: [Double]

    /// A curve through `points`. Sorted by x, duplicates merged, outputs
    /// clamped to `0…1` and made non-decreasing. Fewer than two points is
    /// the identity.
    init(_ points: [CGPoint]) {
        var p = points
            .map { (min(1, max(0, Double($0.x))), min(1, max(0, Double($0.y)))) }
            .filter { $0.0.isFinite && $0.1.isFinite }
            .sorted { $0.0 < $1.0 }
        var merged: [(Double, Double)] = []
        for q in p {
            if let last = merged.last, abs(last.0 - q.0) < 1e-9 { merged[merged.count - 1] = q } else { merged.append(q) }
        }
        p = merged.count >= 2 ? merged : [(0, 0), (1, 1)]
        var running = -Double.infinity
        p = p.map { q in running = max(running, q.1); return (q.0, running) }

        let n = p.count
        let xs = p.map(\.0), ys = p.map(\.1)
        // Spelled out with types: Swift 6.2 (Xcode 26, the CI toolchain) times
        // out type-checking the one-line closure, then reads `d` as Duration.
        var d = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let rise: Double = ys[i + 1] - ys[i]
            let run: Double = xs[i + 1] - xs[i]
            d[i] = rise / run
        }
        var ms = [Double](repeating: 0, count: n)
        ms[0] = d[0]
        ms[n - 1] = d[n - 2]
        for i in 1..<max(1, n - 1) where i < n - 1 {
            ms[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2
        }
        for i in 0..<(n - 1) {
            if d[i] == 0 {
                ms[i] = 0
                ms[i + 1] = 0
                continue
            }
            let a = ms[i] / d[i], b = ms[i + 1] / d[i]
            let s = a * a + b * b
            if s > 9 {
                let t: Double = 3 / s.squareRoot()
                ms[i] = t * a * d[i]
                ms[i + 1] = t * b * d[i]
            }
        }
        self.xs = xs
        self.ys = ys
        self.ms = ms
    }

    /// The curve at `x` in `0…1`; flat before the first point and after the last.
    func eval(_ x: Double) -> Double {
        let n = xs.count
        if x <= xs[0] { return ys[0] }
        if x >= xs[n - 1] { return ys[n - 1] }
        var i = 0
        while i < n - 2 && x >= xs[i + 1] { i += 1 }
        let h = xs[i + 1] - xs[i]
        let t = (x - xs[i]) / h
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * ms[i]
            + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * ms[i + 1]
    }

    /// Whether `points` describe the identity line across the whole range.
    static func isIdentity(_ points: [CGPoint]?) -> Bool {
        guard let points, points.count >= 2 else { return true }
        let sorted = points.sorted { $0.x < $1.x }
        guard let first = sorted.first, let last = sorted.last,
              first.x <= 0.001, last.x >= 0.999 else { return false }
        return sorted.allSatisfy { abs($0.x - $0.y) <= 0.001 }
    }
}
