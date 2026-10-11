//
//  GradingWheel.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One colour-grading wheel: a tint and a lightness shift.
public struct GradingWheel: Codable, Equatable, Sendable {
    /// The tint's hue, sRGB degrees `0…360`.
    public var hue: Double
    /// How strong the tint is, `0…1` (Lightroom's 0…100).
    public var saturation: Double
    /// Lightness shift, `-1…1` (Lightroom's −100…100).
    public var luminance: Double

    public init(hue: Double = 0, saturation: Double = 0, luminance: Double = 0) {
        self.hue = hue
        self.saturation = saturation
        self.luminance = luminance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hue = try c.decodeIfPresent(Double.self, forKey: .hue) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        luminance = try c.decodeIfPresent(Double.self, forKey: .luminance) ?? 0
    }

    /// A wheel with no saturation and no lightness shift does nothing,
    /// whatever its hue.
    public var isIdentity: Bool { saturation == 0 && luminance == 0 }
}
