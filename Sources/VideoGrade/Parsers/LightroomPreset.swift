//
//  LightroomPreset.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Imports Lightroom develop presets (`.xmp`) as a ``VideoGrade``.
///
/// XMP presets are slider recipes, not LUTs — this maps the sliders that
/// have CoreImage analogs (exposure, contrast, saturation, vibrance, white
/// balance, highlights/shadows, sharpening, vignette). Tone curves and
/// per-channel HSL are beyond a slider mapping and are ignored, so imports
/// are a close approximation, not a pixel match.
public enum LightroomPreset {

    /// Parses an `.xmp` develop preset into a grade.
    public static func grade(contentsOf url: URL) throws -> VideoGrade {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return grade(fromXMP: text)
    }

    /// Parses XMP text (attribute or element form) into a grade.
    public static func grade(fromXMP text: String) -> VideoGrade {
        func value(_ key: String) -> Double? {
            // crs:Key="+1.5" (attribute form)
            if let range = text.range(of: "crs:\(key)=\"") {
                let rest = text[range.upperBound...]
                if let end = rest.firstIndex(of: "\"") {
                    return Double(rest[..<end])
                }
            }
            // <crs:Key>+1.5</crs:Key> (element form)
            if let range = text.range(of: "<crs:\(key)>") {
                let rest = text[range.upperBound...]
                if let end = rest.firstIndex(of: "<") {
                    return Double(rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            return nil
        }

        func flag(_ key: String) -> Bool {
            text.range(of: "crs:\(key)=\"True\"") != nil || text.range(of: "<crs:\(key)>True<") != nil
        }

        var grade = VideoGrade()

        if let exposure = value("Exposure2012") {
            grade.exposure = clamp(exposure, -2, 2)
        }
        if let contrast = value("Contrast2012") {
            grade.contrast = clamp(1 + contrast / 100 * 0.5, 0.5, 1.8)
        }
        if flag("ConvertToGrayscale") {
            grade.saturation = 0
        } else if let saturation = value("Saturation") {
            grade.saturation = clamp(1 + saturation / 100, 0, 2)
        }
        if let vibrance = value("Vibrance") {
            grade.vibrance = clamp(vibrance / 100, -1, 1)
        }
        if let highlights = value("Highlights2012") {
            grade.highlights = clamp(1 + highlights / 100 * 0.7, 0.3, 1)
        }
        if let shadows = value("Shadows2012") {
            grade.shadows = clamp(shadows / 100 * 0.7, -0.7, 0.7)
        }
        // Lightroom's default capture sharpening is 40 — treat that as
        // neutral rather than sharpening every import.
        if let sharpness = value("Sharpness") {
            grade.sharpness = clamp((sharpness - 40) / 110 * 1.5, 0, 2)
        }
        if let temperature = value("Temperature"), (2000...20000).contains(temperature) {
            grade.temperature = clamp(temperature, 3500, 9500)
        } else if let incremental = value("IncrementalTemperature") {
            grade.temperature = clamp(6500 + incremental * 25, 3500, 9500)
        }
        if let tint = value("Tint") ?? value("IncrementalTint") {
            grade.tint = clamp(tint, -100, 100)
        }
        if let vignette = value("PostCropVignetteAmount"), vignette < 0 {
            grade.vignette = clamp(-vignette / 100 * 1.5, 0, 2)
        }

        return grade
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}
