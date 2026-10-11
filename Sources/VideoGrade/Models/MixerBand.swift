//
//  MixerBand.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One band of the colour mixer: how far its colours turn, saturate and
/// brighten. Each `-1…1` (Lightroom's −100…100), `0` = untouched.
public struct MixerBand: Codable, Equatable, Sendable {
    public var hue: Double
    public var saturation: Double
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

    public var isIdentity: Bool { hue == 0 && saturation == 0 && luminance == 0 }
}
