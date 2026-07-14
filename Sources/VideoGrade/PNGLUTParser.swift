//
//  PNGLUTParser.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation
import ImageIO

/// Parses image-based 3D LUTs — the square "tiled" PNG format used by many
/// preset packs: a √N×√N grid of N×N tiles, where within a tile x is red,
/// y is green (downward), and the tile index (row-major) is blue.
/// A 512×512 PNG is therefore a 64-point LUT in an 8×8 grid.
public enum PNGLUTParser {

    public enum PNGLUTError: Error, LocalizedError {
        case unreadable
        case unsupportedLayout(width: Int, height: Int)

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                return "The LUT image could not be read."
            case .unsupportedLayout(let width, let height):
                return "Unsupported LUT image layout (\(width)×\(height)); expected a square tiled LUT like 512×512."
            }
        }
    }

    /// Parses a PNG/JPEG LUT into `(dimension, RGBA float32 data)` for
    /// `CIColorCube`.
    public static func parse(contentsOf url: URL) throws -> (dimension: Int, data: Data) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PNGLUTError.unreadable
        }
        return try parse(image: image)
    }

    static func parse(image: CGImage) throws -> (dimension: Int, data: Data) {
        let side = image.width
        guard image.height == side else {
            throw PNGLUTError.unsupportedLayout(width: image.width, height: image.height)
        }

        // side = N·√N  →  N = side^(2/3); require an exact integer grid.
        let dimension = Int(round(pow(Double(side), 2.0 / 3.0)))
        let grid = Int(round(Double(dimension).squareRoot()))
        guard grid * grid == dimension, grid * dimension == side else {
            throw PNGLUTError.unsupportedLayout(width: image.width, height: image.height)
        }

        // Decode into straight RGBA8, top-down rows.
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PNGLUTError.unreadable
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Hot loop over N³ entries (262k for a 64-point LUT) — raw pointers
        // keep it fast even in debug builds.
        var cube = [Float](repeating: 0, count: dimension * dimension * dimension * 4)
        pixels.withUnsafeBufferPointer { source in
            cube.withUnsafeMutableBufferPointer { destination in
                let src = source.baseAddress!
                let dst = destination.baseAddress!
                var cubeIndex = 0
                for blue in 0..<dimension {
                    let tileX = (blue % grid) * dimension
                    let tileY = (blue / grid) * dimension
                    for green in 0..<dimension {
                        // Rows are top-down and green grows downward in this
                        // format, so no flip is needed.
                        var pixel = ((tileY + green) * side + tileX) * 4
                        for _ in 0..<dimension {
                            dst[cubeIndex] = Float(src[pixel]) / 255
                            dst[cubeIndex + 1] = Float(src[pixel + 1]) / 255
                            dst[cubeIndex + 2] = Float(src[pixel + 2]) / 255
                            dst[cubeIndex + 3] = 1
                            pixel += 4
                            cubeIndex += 4
                        }
                    }
                }
            }
        }
        return (dimension, cube.withUnsafeBufferPointer { Data(buffer: $0) })
    }
}
