//
//  ColorMixer.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Lightroom's eight-band colour mixer (HSL panel). Bands are centred on
/// the sRGB hues 0°, 30°, 60°, 120°, 180°, 225°, 270° and 315°, measured
/// in OkLCh, and blend into their neighbours with a raised cosine — so a
/// colour halfway between two bands takes half of each.
public struct ColorMixer: Codable, Equatable, Sendable {
    public var red = MixerBand()
    public var orange = MixerBand()
    public var yellow = MixerBand()
    public var green = MixerBand()
    public var aqua = MixerBand()
    public var blue = MixerBand()
    public var purple = MixerBand()
    public var magenta = MixerBand()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        red = try c.decodeIfPresent(MixerBand.self, forKey: .red) ?? MixerBand()
        orange = try c.decodeIfPresent(MixerBand.self, forKey: .orange) ?? MixerBand()
        yellow = try c.decodeIfPresent(MixerBand.self, forKey: .yellow) ?? MixerBand()
        green = try c.decodeIfPresent(MixerBand.self, forKey: .green) ?? MixerBand()
        aqua = try c.decodeIfPresent(MixerBand.self, forKey: .aqua) ?? MixerBand()
        blue = try c.decodeIfPresent(MixerBand.self, forKey: .blue) ?? MixerBand()
        purple = try c.decodeIfPresent(MixerBand.self, forKey: .purple) ?? MixerBand()
        magenta = try c.decodeIfPresent(MixerBand.self, forKey: .magenta) ?? MixerBand()
    }

    /// The bands in hue order, red first.
    public var bands: [MixerBand] { [red, orange, yellow, green, aqua, blue, purple, magenta] }

    public var isIdentity: Bool { bands.allSatisfy(\.isIdentity) }
}
