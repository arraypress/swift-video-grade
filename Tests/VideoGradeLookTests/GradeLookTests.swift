//
//  GradeLookTests.swift
//  VideoGradeLookTests
//
//  Created by David Sherlock on 2026.
//
//  The look-file shape img and vid wrote with their own copies of this code,
//  proved the same way they proved it: every engine field is in the table,
//  a grade is written as what differs and read back exactly, and a look file
//  from either tool is read strictly.
//

import CoreGraphics
import Foundation
import RecipeKit
import Testing
import VideoGrade
@testable import VideoGradeLook

struct GradeLookTests {

    /// A look file as vid writes it (the same text img's and vid's tests carry).
    static let vidLook = #"""
    {
      "grade" : {
        "black_and_white" : true,
        "color_mixer" : { "blue" : { "saturation" : -0.3 } },
        "contrast" : 1.2,
        "lut" : "film.cube",
        "lut_intensity" : 0.6,
        "temperature" : 7250,
        "tone_curve" : { "shadows" : 0.1 }
      },
      "output" : { "codec" : "hevc", "quality" : 0.8 },
      "vid" : 1
    }
    """#

    struct Holder: Codable, Equatable { var grade: GradeLook }

    @Test func theKeyTableIsTheEngineSFields() throws {
        var grade = VideoGrade(lutURL: URL(fileURLWithPath: "/x.cube"))
        grade.splitShadow = .black
        grade.splitHighlight = .white
        grade.curveRGB = [.zero]
        grade.curveRed = [.zero]
        grade.curveGreen = [.zero]
        grade.curveBlue = [.zero]
        grade.hslBands = [HSLBand()]
        grade.toneCurve = ToneCurve()
        grade.colorMixer = ColorMixer()
        grade.colorGrading = ColorGrading()
        grade.monochromeMix = MonochromeMix()
        let written = try GradeLookJSON.engineObject(grade).keys
        #expect(Set(written) == Set(GradeLookJSON.engineKeys + ["lutURL"]), "every VideoGrade field is in the table")
        #expect(GradeLookJSON.keys.count == Set(GradeLookJSON.keys).count)
        #expect(GradeLookJSON.snake("curveRGB") == "curve_rgb")
        #expect(GradeLookJSON.snake("lutIntensity") == "lut_intensity")
        #expect(GradeLookJSON.snake("bwRed") == "bw_red")
    }

    @Test func aGradeIsWrittenAsWhatDiffersAndReadBackTheSame() throws {
        var grade = VideoGrade(lutURL: URL(fileURLWithPath: "/looks/film.cube"), lutIntensity: 0.6, contrast: 1.2)
        grade.temperatureSlider = 0.3
        grade.blackAndWhite = true
        grade.toneCurve = ToneCurve(shadows: 0.1)
        grade.colorMixer = ColorMixer()
        grade.colorMixer?.blue.saturation = -0.3
        grade.monochromeMix = MonochromeMix()
        grade.curveRGB = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.6), CGPoint(x: 1, y: 1)]
        let holder = Holder(grade: GradeLook(grade))
        let data = try JSONEncoder().encode(holder)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let section = try #require(json["grade"] as? [String: Any])
        #expect(Set(section.keys) == ["lut", "lut_intensity", "contrast", "temperature", "black_and_white",
                                      "tone_curve", "color_mixer", "monochrome_mix", "curve_rgb"])
        #expect(section["tone_curve"] as? [String: Double] == ["shadows": 0.1], "inside a panel, only what differs")
        let back = try JSONDecoder().decode(Holder.self, from: data)
        #expect(back == holder)
        #expect(back.grade.resolved == grade, "the grade the engine runs comes back exactly")
    }

    @Test func anUntouchedLookIsEmpty() throws {
        let data = try JSONEncoder().encode(Holder(grade: GradeLook(VideoGrade())))
        #expect(String(decoding: data, as: UTF8.self) == #"{"grade":{}}"#)
    }

    @Test func aVidLookFileIsReadAndItsLUTFoundBesideIt() throws {
        let look = try LookFile.decoded(Data(Self.vidLook.utf8), folder: URL(fileURLWithPath: "/looks"))
        #expect(look.grade.contrast == 1.2)
        #expect(look.grade.blackAndWhite)
        #expect(look.grade.toneCurve?.shadows == 0.1)
        #expect(look.lut == "/looks/film.cube")
    }

    @Test func aBareGradeSectionIsALookToo() throws {
        let look = try LookFile.decoded(Data(#"{"contrast": 1.3, "vignette": 0.4}"#.utf8), folder: URL(fileURLWithPath: "/"))
        #expect(look.grade.contrast == 1.3)
        #expect(look.grade.vignette == 0.4)
        #expect(look.lut == nil)
    }

    @Test func aMisspeltSettingIsRefusedWithTheCloseOne() {
        #expect(throws: RecipeError("grade.contrats is not a recipe field — did you mean grade.contrast?")) {
            try LookFile.decoded(Data(#"{"grade": {"contrats": 1.2}}"#.utf8), folder: URL(fileURLWithPath: "/"))
        }
        #expect(throws: RecipeError.self) {
            try LookFile.decoded(Data(#"{"grade": {"hsl_bands": [{"hue": 1, "lums": 2}]}}"#.utf8), folder: URL(fileURLWithPath: "/"))
        }
        #expect(throws: RecipeError("it is not JSON")) {
            try LookFile.decoded(Data("nope".utf8), folder: URL(fileURLWithPath: "/"))
        }
    }

    @Test func everySetKindNamesAGradeField() {
        let kinds = GradeLookJSON.kinds(under: "grade").map(\.0)
        #expect(kinds.contains("grade.contrast"))
        #expect(kinds.contains("grade.lut"))
        #expect(kinds.contains("grade.tone_curve.shadows"))
        #expect(Set(kinds).count == kinds.count)
    }
}
