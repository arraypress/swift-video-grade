//
//  GradeColorHex.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  Hex-string parsing for GradeColor, alone and testable. The model states
//  what a color is; how "#FFD60A" becomes components is a rule, and rules
//  live where a test can pin them without constructing a model.
//

import Foundation

/// Parsing for `GradeColor`'s hex form.
enum GradeColorHex {

    /// sRGB components for `"#FFD60A"`, `"FFD60A"`, or `"#FFD60AFF"` (with
    /// alpha); `nil` for malformed input.
    static func components(_ hex: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              let bits = UInt64(value, radix: 16) else { return nil }
        if value.count == 6 {
            return (
                red: Double((bits >> 16) & 0xFF) / 255,
                green: Double((bits >> 8) & 0xFF) / 255,
                blue: Double(bits & 0xFF) / 255,
                alpha: 1
            )
        }
        return (
            red: Double((bits >> 24) & 0xFF) / 255,
            green: Double((bits >> 16) & 0xFF) / 255,
            blue: Double((bits >> 8) & 0xFF) / 255,
            alpha: Double(bits & 0xFF) / 255
        )
    }
}
