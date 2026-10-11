//
//  MonochromeMix.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Lightroom's black & white mix: the image becomes monochrome and each
/// band's colours come out lighter (+) or darker (−) in the grey. Each
/// `-1…1` (Lightroom's −100…100). Setting one on a grade is what turns
/// the Lightroom-style conversion on; an all-zero mix is a plain
/// lightness-preserving black & white.
public struct MonochromeMix: Codable, Equatable, Sendable {
    public var red: Double = 0
    public var orange: Double = 0
    public var yellow: Double = 0
    public var green: Double = 0
    public var aqua: Double = 0
    public var blue: Double = 0
    public var purple: Double = 0
    public var magenta: Double = 0

    public init(red: Double = 0, orange: Double = 0, yellow: Double = 0, green: Double = 0,
                aqua: Double = 0, blue: Double = 0, purple: Double = 0, magenta: Double = 0) {
        self.red = red
        self.orange = orange
        self.yellow = yellow
        self.green = green
        self.aqua = aqua
        self.blue = blue
        self.purple = purple
        self.magenta = magenta
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        red = try c.decodeIfPresent(Double.self, forKey: .red) ?? 0
        orange = try c.decodeIfPresent(Double.self, forKey: .orange) ?? 0
        yellow = try c.decodeIfPresent(Double.self, forKey: .yellow) ?? 0
        green = try c.decodeIfPresent(Double.self, forKey: .green) ?? 0
        aqua = try c.decodeIfPresent(Double.self, forKey: .aqua) ?? 0
        blue = try c.decodeIfPresent(Double.self, forKey: .blue) ?? 0
        purple = try c.decodeIfPresent(Double.self, forKey: .purple) ?? 0
        magenta = try c.decodeIfPresent(Double.self, forKey: .magenta) ?? 0
    }

    /// The bands in hue order, red first.
    public var bands: [Double] { [red, orange, yellow, green, aqua, blue, purple, magenta] }
}
