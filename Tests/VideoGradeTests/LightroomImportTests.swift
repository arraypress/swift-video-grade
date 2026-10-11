//
//  LightroomImportTests.swift
//  VideoGradeTests
//
//  Created by David Sherlock on 2026.
//
//  Hand-written presets in both of Lightroom's XMP forms: every mapped
//  setting lands where it should, and what is set but not reproduced is
//  listed — neither more (metadata, defaults) nor less.
//

import CoreGraphics
import Foundation
import Testing
@testable import VideoGrade

private func preset(_ name: String) throws -> LightroomImport {
    guard let url = Bundle.module.url(forResource: name, withExtension: "xmp", subdirectory: "Fixtures") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try LightroomPreset.importPreset(contentsOf: url)
}

private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

@Suite("Lightroom import")
struct LightroomImportTests {

    @Test("Attribute form: every mapped setting lands")
    func attributeForm() throws {
        let imported = try preset("preset-attributes")
        let g = imported.grade
        #expect(close(g.exposure, 0.5) && close(g.contrast, 1.1) && close(g.vibrance, 0.12))
        #expect(close(g.saturation, 0.92))
        #expect(close(g.whites, 0.15) && close(g.blacks, -0.25))
        #expect(close(g.texture, 0.1) && close(g.clarity, -0.2) && close(g.hazeRemoval, 0.35))
        #expect(close(g.grain, 0.2) && close(g.vignette, 0.225))
        let curve = try #require(g.toneCurve)
        #expect(close(curve.shadows, -0.1) && close(curve.darks, 0.05) && close(curve.lights, 0.15) && close(curve.highlights, -0.2))
        #expect(close(curve.shadowSplit, 0.2) && close(curve.midtoneSplit, 0.5) && close(curve.highlightSplit, 0.8))
        let mixer = try #require(g.colorMixer)
        #expect(close(mixer.orange.hue, -0.1) && close(mixer.blue.saturation, -0.4) && close(mixer.green.luminance, 0.25))
        #expect(mixer.red.isIdentity && mixer.aqua.isIdentity)
        let grading = try #require(g.colorGrading)
        #expect(close(grading.shadows.hue, 215) && close(grading.shadows.saturation, 0.2) && close(grading.shadows.luminance, -0.05))
        #expect(close(grading.highlights.hue, 40) && close(grading.highlights.saturation, 0.15))
        #expect(close(grading.midtones.hue, 30) && close(grading.midtones.saturation, 0.08))
        #expect(close(grading.blending, 0.6) && close(grading.balance, -0.1))
        #expect(g.monochromeMix == nil)
    }

    @Test("Attribute form: only the set, unmapped settings are reported")
    func attributeUnsupported() throws {
        let imported = try preset("preset-attributes")
        print("UNSUPPORTED (attributes): \(imported.unsupported)")
        // Not reported: metadata (PresetType, UUID, Version…), Lightroom's own
        // defaults (SharpenRadius 1, SharpenDetail 25, GrainFrequency 50,
        // PostCropVignetteMidpoint 50), zeros (AutoLateralCA) and names.
        #expect(imported.unsupported == [
            "CameraProfile=Camera Vivid", "GrainSize=40", "LensProfileEnable=1", "LuminanceSmoothing=10",
        ])
    }

    @Test("Element form: curves from rdf:Seq, black & white, and the blocks reported")
    func elementForm() throws {
        let imported = try preset("preset-elements")
        let g = imported.grade
        let curve = try #require(g.toneCurve)
        let master = try #require(curve.master)
        #expect(master.count == 4)
        #expect(close(Double(master[0].y), 12.0 / 255) && close(Double(master[3].x), 1))
        #expect(MonotoneCurve.isIdentity(curve.red))
        #expect(curve.blue?.count == 3)
        let mono = try #require(g.monochromeMix)
        #expect(close(mono.red, 0.2) && close(mono.blue, -0.3) && mono.green == 0)
        #expect(close(g.colorGrading?.global.hue ?? 0, 200) && close(g.colorGrading?.global.saturation ?? 0, 0.1))
        #expect(g.vignette == 0)
        // A mask's own settings stay inside the mask.
        #expect(g.exposure == 0)
        print("UNSUPPORTED (elements): \(imported.unsupported)")
        #expect(imported.unsupported == [
            "PostCropVignetteAmount=+20", "ToneCurve", "masks", "profile look (Look)",
        ])
    }

    @Test("The old entry point still returns just the grade")
    func legacyEntryPoint() throws {
        let text = #"<rdf:Description crs:Exposure2012="+1.00" crs:Dehaze="-50"/>"#
        let grade = LightroomPreset.grade(fromXMP: text)
        #expect(close(grade.exposure, 1) && close(grade.hazeRemoval, -0.5))
        #expect(LightroomPreset.importPreset(fromXMP: text).unsupported.isEmpty)
    }

    @Test("An imported preset renders without error and is not neutral")
    func renders() throws {
        for name in ["preset-attributes", "preset-elements"] {
            let grade = try preset(name).grade
            #expect(!grade.isNeutral)
            let px = try SyntheticScene.graded(grade, SyntheticScene.golden())
            let finite = px.allSatisfy { $0.isFinite }
            #expect(finite)
        }
    }
}
