//
//  DevelopCube.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  The per-pixel Lightroom controls — whites/blacks, the colour mixer,
//  black & white, colour grading and the tone curve — baked into one cube
//  over squeezed values (see RangeShaper), in LightCraft's order: tone,
//  then colour, then the curve on display-encoded values.
//

import CoreImage
import Foundation

/// Bakes the develop controls into a colour cube.
enum DevelopCube {

    /// Lattice points per axis. 64 puts about 50 points across the SDR range.
    static let dimension = 64

    /// Whether any per-pixel develop control is on.
    static func isActive(_ grade: VideoGrade) -> Bool {
        grade.whites != 0 || grade.blacks != 0
            || grade.toneCurve.map { !$0.isIdentity } == true
            || DevelopColor(grade: grade).isActive
    }

    /// RGBA-float cube data, or `nil` when nothing per-pixel is on.
    static func data(for grade: VideoGrade) -> Data? {
        guard isActive(grade) else { return nil }
        let color = DevelopColor(grade: grade)
        let curves = grade.toneCurve.flatMap(ToneCurveMath.tables)
        let whites = min(1, max(-1, grade.whites)), blacks = min(1, max(-1, grade.blacks))
        let n = dimension
        let axis = (0..<n).map { RangeShaper.stretch(Double($0) / Double(n - 1)) }
        var out = [Float](repeating: 0, count: n * n * n * 4)
        var index = 0
        for bi in 0..<n {
            for gi in 0..<n {
                for ri in 0..<n {
                    let (r, g, b) = transform(axis[ri], axis[gi], axis[bi], whites: whites, blacks: blacks,
                                              color: color, curves: curves)
                    out[index] = Float(RangeShaper.squeeze(r))
                    out[index + 1] = Float(RangeShaper.squeeze(g))
                    out[index + 2] = Float(RangeShaper.squeeze(b))
                    out[index + 3] = 1
                    index += 4
                }
            }
        }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// One display-encoded colour through the develop controls.
    static func transform(_ r: Double, _ g: Double, _ b: Double, whites: Double, blacks: Double,
                          color: DevelopColor, curves: [[Double]]?) -> (Double, Double, Double) {
        var lin = (OkLab.decode(r), OkLab.decode(g), OkLab.decode(b))
        if whites != 0 || blacks != 0 {
            lin = DevelopTone.whitesBlacks(lin.0, lin.1, lin.2, whites: whites, blacks: blacks)
        }
        if color.isActive {
            lin = color.apply(max(0, lin.0), max(0, lin.1), max(0, lin.2))
        }
        var enc = (OkLab.encode(lin.0), OkLab.encode(lin.1), OkLab.encode(lin.2))
        if let curves {
            enc = (ToneCurveMath.eval(curves[0], enc.0), ToneCurveMath.eval(curves[1], enc.1),
                   ToneCurveMath.eval(curves[2], enc.2))
        }
        return enc
    }
}
