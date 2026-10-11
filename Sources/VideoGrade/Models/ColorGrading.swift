//
//  ColorGrading.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Lightroom's three-way colour grading: shadows, midtones and highlights
/// wheels plus a global one. The tonal ranges are read from OkLab
/// lightness; `blending` widens their overlap and `balance` slides the
/// shadows/highlights boundary. Legacy split toning maps onto the
/// shadows and highlights wheels.
public struct ColorGrading: Codable, Equatable, Sendable {
    public var shadows = GradingWheel()
    public var midtones = GradingWheel()
    public var highlights = GradingWheel()
    public var global = GradingWheel()
    /// Overlap of the ranges, `0…1` (Lightroom's 0…100; default 50).
    public var blending: Double = 0.5
    /// Shadows (−) to highlights (+) emphasis, `-1…1`.
    public var balance: Double = 0

    public init(shadows: GradingWheel = GradingWheel(), midtones: GradingWheel = GradingWheel(),
                highlights: GradingWheel = GradingWheel(), global: GradingWheel = GradingWheel(),
                blending: Double = 0.5, balance: Double = 0) {
        self.shadows = shadows
        self.midtones = midtones
        self.highlights = highlights
        self.global = global
        self.blending = blending
        self.balance = balance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shadows = try c.decodeIfPresent(GradingWheel.self, forKey: .shadows) ?? GradingWheel()
        midtones = try c.decodeIfPresent(GradingWheel.self, forKey: .midtones) ?? GradingWheel()
        highlights = try c.decodeIfPresent(GradingWheel.self, forKey: .highlights) ?? GradingWheel()
        global = try c.decodeIfPresent(GradingWheel.self, forKey: .global) ?? GradingWheel()
        blending = try c.decodeIfPresent(Double.self, forKey: .blending) ?? 0.5
        balance = try c.decodeIfPresent(Double.self, forKey: .balance) ?? 0
    }

    /// No wheel does anything; blending and balance alone move no pixel.
    public var isIdentity: Bool {
        shadows.isIdentity && midtones.isIdentity && highlights.isIdentity && global.isIdentity
    }
}
