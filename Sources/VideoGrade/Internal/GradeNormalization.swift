//
//  GradeNormalization.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  The inert-settings rule, alone and testable: which fields ride along
//  without touching a pixel because the amount that would apply them is
//  off. `isNeutral` is only trustworthy because this is exhaustive, so it
//  lives here as a pure function rather than inside the model.
//

import Foundation

/// Folding a grade's inert settings back to their defaults.
enum GradeNormalization {

    /// `source` with every setting that grades nothing put back to its
    /// default, so semantically identical grades compare equal.
    static func normalized(_ source: VideoGrade) -> VideoGrade {
        var grade = source
        if grade.lutURL == nil || grade.lutIntensity == 0 {
            grade.lutURL = nil
            grade.lutIntensity = 1
        }
        if grade.glow == 0 { grade.glowRadius = 25 }
        if grade.halation == 0 { grade.halationRadius = 30 }
        if grade.lightLeak == 0 { grade.lightLeakStyle = 0 }
        if grade.splitShadow == nil || grade.splitShadowAmount == 0 {
            grade.splitShadow = nil
            grade.splitShadowAmount = 0
        }
        if grade.splitHighlight == nil || grade.splitHighlightAmount == 0 {
            grade.splitHighlight = nil
            grade.splitHighlightAmount = 0
        }
        if !grade.blackAndWhite {
            grade.bwRed = 0; grade.bwOrange = 0; grade.bwYellow = 0; grade.bwGreen = 0
            grade.bwAqua = 0; grade.bwBlue = 0; grade.bwPurple = 0; grade.bwMagenta = 0
        }
        if !ColorGradeCube.isActive(grade.curveRGB) { grade.curveRGB = nil }
        if !ColorGradeCube.isActive(grade.curveRed) { grade.curveRed = nil }
        if !ColorGradeCube.isActive(grade.curveGreen) { grade.curveGreen = nil }
        if !ColorGradeCube.isActive(grade.curveBlue) { grade.curveBlue = nil }
        // The cube only reads a complete 12-band set; anything else is inert.
        if let bands = grade.hslBands, bands.count != 12 || bands.allSatisfy(\.isIdentity) {
            grade.hslBands = nil
        }
        if grade.toneCurve?.isIdentity == true { grade.toneCurve = nil }
        if grade.colorMixer?.isIdentity == true { grade.colorMixer = nil }
        if grade.colorGrading?.isIdentity == true { grade.colorGrading = nil }
        return grade
    }
}
