//
//  ModelBehaviorTests.swift
//  VideoGradeTests
//
//  Created by David Sherlock on 2026.
//
//  The rules that used to live inside the models, pinned directly — hex
//  parsing without constructing a color, normalization without comparing
//  through Equatable side doors.
//

import Testing
@testable import VideoGrade

@Suite("Model behavior extracted")
struct ModelBehaviorTests {

    @Test("Hex parsing pins exact components")
    func hexParsing() {
        let red = GradeColorHex.components("FF0000")
        #expect(red != nil && red! == (red: 1, green: 0, blue: 0, alpha: 1))
        let hashed = GradeColorHex.components("#FFD60A")
        #expect(hashed != nil && abs(hashed!.green - 0.84) < 0.01)
        let alpha = GradeColorHex.components("#00000080")
        #expect(alpha != nil && abs(alpha!.alpha - 128.0 / 255.0) < 0.001)
        let padded = GradeColorHex.components("  FFFFFF  ")
        #expect(padded != nil && padded!.red == 1)
        #expect(GradeColorHex.components("nope") == nil)
        #expect(GradeColorHex.components("12345") == nil)
        #expect(GradeColor(hex: "#FF0000") == GradeColor(red: 1, green: 0, blue: 0))
    }

    @Test("Normalization folds inert settings")
    func normalization() {
        var grade = VideoGrade()
        grade.glowRadius = 99            // glow itself is off
        grade.bwRed = 0.5                // blackAndWhite is off
        grade.hslBands = Array(repeating: HSLBand(hue: 0.2), count: 11)  // incomplete set
        let folded = GradeNormalization.normalized(grade)
        #expect(folded.glowRadius == 25)
        #expect(folded.bwRed == 0)
        #expect(folded.hslBands == nil)
        #expect(grade.isNeutral)

        var active = VideoGrade()
        active.glow = 0.5
        active.glowRadius = 12
        #expect(GradeNormalization.normalized(active).glowRadius == 12)
        #expect(!active.isNeutral)
    }
}
