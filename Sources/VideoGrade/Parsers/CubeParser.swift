//
//  CubeParser.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Parses Adobe/Resolve `.cube` LUT files into `CIColorCube` data.
///
/// `DOMAIN_MIN`/`DOMAIN_MAX` lines are accepted and ignored — the cube is
/// applied over the full 0…1 domain, which is what every mainstream preset
/// pack ships. A cube authored for a narrower domain would grade slightly
/// differently, and none has turned up in practice.
public enum CubeParser {

    public enum CubeError: Error, LocalizedError, Equatable {
        case unreadable
        case missingSize
        case unsupportedSize(Int)
        case wrongEntryCount(expected: Int, got: Int)

        public var errorDescription: String? {
            switch self {
            case .unreadable: return "The LUT file could not be read."
            case .missingSize: return "The LUT file has no LUT_3D_SIZE."
            case .unsupportedSize(let size):
                return "The LUT declares a size of \(size); 2–128 is supported."
            case .wrongEntryCount(let expected, let got):
                return "The LUT has \(got) entries; expected \(expected)."
            }
        }
    }

    /// The largest cube edge `CIColorCube` accepts. Also the guard that stops
    /// a corrupt size line asking for a multi-gigabyte allocation: the
    /// entry count grows with the cube of this number.
    public static let maximumDimension = 128

    /// Parses a `.cube` file into `(dimension, RGBA float32 data)`.
    public static func parse(contentsOf url: URL) throws -> (dimension: Int, data: Data) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw CubeError.unreadable
        }
        return try parse(text)
    }

    public static func parse(_ text: String) throws -> (dimension: Int, data: Data) {
        var dimension = 0
        var values: [Float] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let upper = line.uppercased()
            if upper.hasPrefix("LUT_3D_SIZE") {
                dimension = Int(line.split(separator: " ").last.map(String.init) ?? "") ?? 0
                // Bounded before anything is allocated: the declared size is
                // untrusted input, and 200 would already mean a gigabyte of
                // floats for a cube Core Image cannot use anyway.
                guard dimension <= Self.maximumDimension else {
                    throw CubeError.unsupportedSize(dimension)
                }
                values.reserveCapacity(dimension * dimension * dimension * 4)
                continue
            }
            if upper.hasPrefix("TITLE") || upper.hasPrefix("DOMAIN_") || upper.hasPrefix("LUT_1D") { continue }

            let parts = line.split(separator: " ").compactMap { Float($0) }
            if parts.count == 3 {
                values.append(contentsOf: [parts[0], parts[1], parts[2], 1])
            }
        }

        guard dimension > 1 else { throw CubeError.missingSize }
        let expected = dimension * dimension * dimension * 4
        guard values.count == expected else {
            throw CubeError.wrongEntryCount(expected: expected / 4, got: values.count / 4)
        }
        return (dimension, values.withUnsafeBufferPointer { Data(buffer: $0) })
    }
}
