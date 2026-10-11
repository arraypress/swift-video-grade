//
//  SyntheticScene.swift
//  VideoGradeTests
//
//  Created by David Sherlock on 2026.
//
//  Generated test images in linear light — no external assets — and a
//  float renderer, so every develop control is measured rather than
//  eyeballed. Values above 1 and partial alpha are first-class.
//

import CoreImage
import Foundation
@testable import VideoGrade

/// Synthetic linear scenes and float readback.
enum SyntheticScene {

    static let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An image from a function of pixel position returning straight
    /// (unpremultiplied) linear RGBA.
    static func image(width: Int, height: Int,
                      _ pixel: (Int, Int) -> (Double, Double, Double, Double)) -> CIImage {
        var data = [Float](); data.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = pixel(x, y)
                data += [Float(r * a), Float(g * a), Float(b * a), Float(a)]
            }
        }
        return CIImage(bitmapData: data.withUnsafeBufferPointer { Data(buffer: $0) }, bytesPerRow: width * 16,
                       size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: linear)
    }

    /// A one-row image of the given straight linear colours.
    static func row(_ colours: [(Double, Double, Double, Double)]) -> CIImage {
        image(width: colours.count, height: 1) { x, _ in colours[x] }
    }

    /// Premultiplied linear RGBA floats of `image`, rendered in `working`.
    static func render(_ image: CIImage, working: CGColorSpace = linear) -> [Float] {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var out = [Float](repeating: 0, count: w * h * 4)
        CIContext(options: [.workingColorSpace: working, .workingFormat: CIFormat.RGBAf])
            .render(image, toBitmap: &out, rowBytes: w * 16, bounds: image.extent, format: .RGBAf, colorSpace: linear)
        return out
    }

    /// Straight colour of pixel `i` from premultiplied floats.
    static func colour(_ px: [Float], _ i: Int) -> (Double, Double, Double, Double) {
        let a = Double(px[i * 4 + 3])
        guard a > 0 else { return (0, 0, 0, 0) }
        return (Double(px[i * 4]) / a, Double(px[i * 4 + 1]) / a, Double(px[i * 4 + 2]) / a, a)
    }

    /// A grade applied to `image`, rendered.
    static func graded(_ grade: VideoGrade, _ image: CIImage, working: CGColorSpace = linear) throws -> [Float] {
        render(try GradeFilter(grade: grade).apply(image, time: 0), working: working)
    }

    /// A fully saturated, value-`v` sRGB colour at HSV hue `degrees`, linear.
    static func hue(_ degrees: Double, saturation: Double = 0.8, value: Double = 0.8) -> (Double, Double, Double, Double) {
        let (r, g, b) = OkLab.hsvToRGB(degrees / 360, saturation, value)
        return (OkLab.decode(r), OkLab.decode(g), OkLab.decode(b), 1)
    }

    /// The golden scene 0.1.1 was rendered on — built in Float exactly as
    /// it was then, so the comparison is bit-for-bit.
    static func golden() -> CIImage {
        let side = 48
        var px = [Float](); px.reserveCapacity(side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let u = Float(x) / Float(side - 1), v = Float(y) / Float(side - 1)
                px += [u * u, v * 0.8, (1 - u) * v, 1]
            }
        }
        return CIImage(bitmapData: px.withUnsafeBufferPointer { Data(buffer: $0) }, bytesPerRow: side * 16,
                       size: CGSize(width: side, height: side), format: .RGBAf, colorSpace: linear)
    }
}
