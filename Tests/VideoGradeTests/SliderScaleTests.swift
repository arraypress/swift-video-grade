//
//  SliderScaleTests.swift
//  VideoGradeTests
//
//  Created by David Sherlock on 2026.
//
//  The slider scale every caller binds to. img 0.6.0 put −1…1 straight into
//  Kelvin and every temperature came out the same blue; these pin the scale
//  so a caller cannot get that wrong again.
//

import Testing
@testable import VideoGrade

@Suite("Slider scale")
struct SliderScaleTests {

    @Test("Zero is untouched for every slider")
    func zeroIsNeutral() {
        var grade = VideoGrade()
        grade.temperatureSlider = 0
        grade.tintSlider = 0
        grade.highlightRecovery = 0
        #expect(grade.temperature == 6500)
        #expect(grade.tint == 0)
        #expect(grade.highlights == 1)
    }

    @Test("Opposite temperature sliders give different white balances")
    func temperatureSpreads() {
        var cool = VideoGrade(), warm = VideoGrade()
        cool.temperatureSlider = -1
        warm.temperatureSlider = 1
        #expect(cool.temperature == 4000)
        #expect(warm.temperature == 9000)
    }

    @Test("Sliders round-trip and clamp", arguments: [-1.0, -0.25, 0, 0.5, 1])
    func roundTrip(_ value: Double) {
        var grade = VideoGrade()
        grade.temperatureSlider = value
        grade.tintSlider = value
        #expect(abs(grade.temperatureSlider - value) < 1e-12)
        #expect(abs(grade.tintSlider - value) < 1e-12)
        grade.highlightRecovery = abs(value)
        #expect(abs(grade.highlightRecovery - abs(value)) < 1e-12)

        grade.temperatureSlider = value * 5
        #expect((4000...9000).contains(grade.temperature))
        grade.highlightRecovery = -1
        #expect(grade.highlights == 1)
    }

    @Test("Full recovery reaches the floor the importer uses")
    func recoveryFloor() {
        var grade = VideoGrade()
        grade.highlightRecovery = 1
        #expect(abs(grade.highlights - SliderScale.highlightFloor) < 1e-12)
    }
}
