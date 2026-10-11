//
//  SliderScale.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  One slider scale for every caller — a CLI flag, an app slider, a preset —
//  onto the engine's own units, which are not sliders: temperature is
//  Kelvin, tint ±100, highlights a Core Image amount where 1 is untouched.
//  img 0.6.0 passed flag values straight through and every --temperature
//  came out the same blue; the scale lives here so no caller repeats that.
//

/// Slider ↔ engine units. Sliders are `-1…1` (recovery `0…1`), `0` untouched.
enum SliderScale {

    /// Kelvin either side of neutral that a full slider reaches —
    /// Lightroom's ±100 incremental temperature at 25 K a step.
    static let kelvinSpan = 2500.0

    /// The strongest highlight recovery: Core Image amount 0.3.
    static let highlightFloor = 0.3

    static func kelvin(_ slider: Double) -> Double { 6500 + clamp(slider) * kelvinSpan }
    static func slider(kelvin: Double) -> Double { (kelvin - 6500) / kelvinSpan }

    static func tint(_ slider: Double) -> Double { clamp(slider) * 100 }
    static func slider(tint: Double) -> Double { tint / 100 }

    static func highlights(recovery: Double) -> Double {
        1 - min(1, max(0, recovery)) * (1 - highlightFloor)
    }
    static func recovery(highlights: Double) -> Double { (1 - highlights) / (1 - highlightFloor) }

    private static func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }
}
