//
//  LightroomPreset.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Imports Lightroom develop presets (`.xmp`) as a ``VideoGrade``.
///
/// Maps the basic panel, whites/blacks, texture, clarity, dehaze, the tone
/// curve (parametric and point), the colour mixer, black & white mix,
/// colour grading and split toning, dark vignette and grain amount. What a
/// preset sets beyond that — camera profiles and looks, masks, lens
/// corrections, noise reduction — is listed in
/// ``LightroomImport/unsupported`` by ``importPreset(fromXMP:)``.
public enum LightroomPreset {

    /// Parses an `.xmp` develop preset into a grade and what it could not apply.
    public static func importPreset(contentsOf url: URL) throws -> LightroomImport {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return importPreset(fromXMP: text)
    }

    /// Parses XMP text (attribute or element form) into a grade and what it
    /// could not apply.
    public static func importPreset(fromXMP text: String) -> LightroomImport {
        LightroomMapping.importPreset(XMPSettings(text))
    }

    /// Parses an `.xmp` develop preset into a grade.
    public static func grade(contentsOf url: URL) throws -> VideoGrade {
        try importPreset(contentsOf: url).grade
    }

    /// Parses XMP text (attribute or element form) into a grade.
    public static func grade(fromXMP text: String) -> VideoGrade {
        importPreset(fromXMP: text).grade
    }
}
