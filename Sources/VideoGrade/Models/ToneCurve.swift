//
//  ToneCurve.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// Lightroom's tone curve: the parametric region curve (shadows, darks,
/// lights, highlights between three movable splits) followed by point
/// curves for all channels and for red, green and blue.
///
/// Points are display-encoded `0…1` (x = input, y = output). They are
/// interpolated monotonically — a curve can flatten but never invert a
/// tone, whatever order its points arrive in.
public struct ToneCurve: Codable, Equatable, Sendable {

    /// Region amounts, `-1…1` (Lightroom's −100…100), `0` = untouched.
    public var shadows: Double = 0
    public var darks: Double = 0
    public var lights: Double = 0
    public var highlights: Double = 0

    /// Where the regions meet, `0…1` (Lightroom's 25 / 50 / 75 by default).
    public var shadowSplit: Double = 0.25
    public var midtoneSplit: Double = 0.5
    public var highlightSplit: Double = 0.75

    /// Point curves; `nil` (or the identity line) = untouched. `master`
    /// shapes all three channels, the others one channel each, after it.
    public var master: [CGPoint]?
    public var red: [CGPoint]?
    public var green: [CGPoint]?
    public var blue: [CGPoint]?

    public init(shadows: Double = 0, darks: Double = 0, lights: Double = 0, highlights: Double = 0,
                shadowSplit: Double = 0.25, midtoneSplit: Double = 0.5, highlightSplit: Double = 0.75,
                master: [CGPoint]? = nil, red: [CGPoint]? = nil, green: [CGPoint]? = nil, blue: [CGPoint]? = nil) {
        self.shadows = shadows
        self.darks = darks
        self.lights = lights
        self.highlights = highlights
        self.shadowSplit = shadowSplit
        self.midtoneSplit = midtoneSplit
        self.highlightSplit = highlightSplit
        self.master = master
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        darks = try c.decodeIfPresent(Double.self, forKey: .darks) ?? 0
        lights = try c.decodeIfPresent(Double.self, forKey: .lights) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadowSplit = try c.decodeIfPresent(Double.self, forKey: .shadowSplit) ?? 0.25
        midtoneSplit = try c.decodeIfPresent(Double.self, forKey: .midtoneSplit) ?? 0.5
        highlightSplit = try c.decodeIfPresent(Double.self, forKey: .highlightSplit) ?? 0.75
        master = try c.decodeIfPresent([CGPoint].self, forKey: .master)
        red = try c.decodeIfPresent([CGPoint].self, forKey: .red)
        green = try c.decodeIfPresent([CGPoint].self, forKey: .green)
        blue = try c.decodeIfPresent([CGPoint].self, forKey: .blue)
    }

    /// Whether the curve changes no tone.
    public var isIdentity: Bool { ToneCurveMath.isIdentity(self) }
}
