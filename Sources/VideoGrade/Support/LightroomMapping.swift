//
//  LightroomMapping.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  Camera Raw settings → a VideoGrade. Lightroom sliders run −100…100 and
//  map to −1…1 here; the basic panel keeps the 0.1.x mapping onto the
//  engine's Core Image stages. Whatever is set and not mapped is reported,
//  never dropped silently.
//

import CoreGraphics
import Foundation

/// Maps a preset's settings onto the engine.
enum LightroomMapping {

    /// The band suffixes Lightroom uses, red first — the order of
    /// ``ColorMixer/bands`` and ``MonochromeMix/bands``.
    static let bandNames = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]

    static func importPreset(_ xmp: XMPSettings) -> LightroomImport {
        var used = Set<String>()
        func num(_ key: String) -> Double? {
            used.insert(key)
            return xmp.number(key)
        }
        func unit(_ key: String) -> Double? { num(key).map { min(1, max(-1, $0 / 100)) } }
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

        var grade = VideoGrade()

        // Basic panel — as in 0.1.x.
        if let v = num("Exposure2012") { grade.exposure = clamp(v, -2, 2) }
        if let v = num("Contrast2012") { grade.contrast = clamp(1 + v / 100 * 0.5, 0.5, 1.8) }
        if let v = num("Saturation") { grade.saturation = clamp(1 + v / 100, 0, 2) }
        if let v = num("Vibrance") { grade.vibrance = clamp(v / 100, -1, 1) }
        if let v = num("Highlights2012") { grade.highlights = SliderScale.highlights(recovery: -v / 100) }
        if let v = num("Shadows2012") { grade.shadows = clamp(v / 100 * 0.7, -0.7, 0.7) }
        // Lightroom's default capture sharpening is 40 — neutral here.
        if let v = num("Sharpness") { grade.sharpness = clamp((v - 40) / 110 * 1.5, 0, 2) }
        used.formUnion(["Temperature", "IncrementalTemperature", "Tint", "IncrementalTint", "WhiteBalance"])
        if let t = xmp.number("Temperature"), (2000...20000).contains(t) {
            grade.temperature = clamp(t, 3500, 9500)
        } else if let i = xmp.number("IncrementalTemperature") {
            grade.temperature = SliderScale.kelvin(i / 100)
        }
        if let t = xmp.number("Tint") ?? xmp.number("IncrementalTint") { grade.tint = SliderScale.tint(t / 100) }

        // Whites, blacks, presence.
        if let v = unit("Whites2012") { grade.whites = v }
        if let v = unit("Blacks2012") { grade.blacks = v }
        if let v = unit("Clarity2012") { grade.clarity = v }
        if let v = unit("Texture") { grade.texture = v }
        if let v = unit("Dehaze") { grade.hazeRemoval = v }

        // Effects: vignette (dark only) and grain amount.
        // Only a darkening vignette maps; a white one is reported.
        if let v = xmp.number("PostCropVignetteAmount"), v <= 0 {
            used.insert("PostCropVignetteAmount")
            grade.vignette = clamp(-v / 100 * 1.5, 0, 2)
        }
        if let v = num("GrainAmount") { grade.grain = clamp(v / 100, 0, 1) }

        // Tone curve.
        var curve = ToneCurve()
        if let v = unit("ParametricShadows") { curve.shadows = v }
        if let v = unit("ParametricDarks") { curve.darks = v }
        if let v = unit("ParametricLights") { curve.lights = v }
        if let v = unit("ParametricHighlights") { curve.highlights = v }
        if let v = num("ParametricShadowSplit") { curve.shadowSplit = v / 100 }
        if let v = num("ParametricMidtoneSplit") { curve.midtoneSplit = v / 100 }
        if let v = num("ParametricHighlightSplit") { curve.highlightSplit = v / 100 }
        curve.master = xmp.points("ToneCurvePV2012")
        curve.red = xmp.points("ToneCurvePV2012Red")
        curve.green = xmp.points("ToneCurvePV2012Green")
        curve.blue = xmp.points("ToneCurvePV2012Blue")
        used.formUnion(["ToneCurvePV2012", "ToneCurvePV2012Red", "ToneCurvePV2012Green", "ToneCurvePV2012Blue"])
        if !curve.isIdentity { grade.toneCurve = curve }

        // Colour mixer.
        var mixer = ColorMixer()
        var bands = mixer.bands
        for (i, name) in bandNames.enumerated() {
            if let v = unit("HueAdjustment\(name)") { bands[i].hue = v }
            if let v = unit("SaturationAdjustment\(name)") { bands[i].saturation = v }
            if let v = unit("LuminanceAdjustment\(name)") { bands[i].luminance = v }
        }
        (mixer.red, mixer.orange, mixer.yellow, mixer.green) = (bands[0], bands[1], bands[2], bands[3])
        (mixer.aqua, mixer.blue, mixer.purple, mixer.magenta) = (bands[4], bands[5], bands[6], bands[7])
        if !mixer.isIdentity { grade.colorMixer = mixer }

        // Black & white.
        used.insert("ConvertToGrayscale")
        let grey = bandNames.map { unit("GrayMixer\($0)") ?? 0 }
        if xmp.flag("ConvertToGrayscale") {
            grade.monochromeMix = MonochromeMix(red: grey[0], orange: grey[1], yellow: grey[2], green: grey[3],
                                                aqua: grey[4], blue: grey[5], purple: grey[6], magenta: grey[7])
        }

        // Colour grading; split toning is its shadows/highlights wheels.
        func wheel(_ hue: [String], _ sat: [String], _ lum: String?) -> GradingWheel {
            let h = hue.lazy.compactMap { num($0) }.first ?? 0
            let s = sat.lazy.compactMap { num($0) }.first ?? 0
            let l = lum.flatMap { unit($0) } ?? 0
            return GradingWheel(hue: h, saturation: clamp(s / 100, 0, 1), luminance: l)
        }
        var grading = ColorGrading(
            shadows: wheel(["ColorGradeShadowHue", "SplitToningShadowHue"], ["ColorGradeShadowSat", "SplitToningShadowSaturation"], "ColorGradeShadowLum"),
            midtones: wheel(["ColorGradeMidtoneHue"], ["ColorGradeMidtoneSat"], "ColorGradeMidtoneLum"),
            highlights: wheel(["ColorGradeHighlightHue", "SplitToningHighlightHue"], ["ColorGradeHighlightSat", "SplitToningHighlightSaturation"], "ColorGradeHighlightLum"),
            global: wheel(["ColorGradeGlobalHue"], ["ColorGradeGlobalSat"], "ColorGradeGlobalLum"))
        if let v = num("ColorGradeBlending") { grading.blending = clamp(v / 100, 0, 1) }
        if let v = unit("SplitToningBalance") { grading.balance = v }
        if !grading.isIdentity { grade.colorGrading = grading }

        return LightroomImport(grade: grade, unsupported: unsupported(xmp, used: used))
    }

    // MARK: - What is left over

    /// Set, unmapped settings: anything not metadata and not at
    /// Lightroom's own default.
    static func unsupported(_ xmp: XMPSettings, used: Set<String>) -> [String] {
        var out: [String] = []
        for (key, value) in xmp.values where !used.contains(key) && !metadata.contains(key) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if let n = Double(trimmed) {
                if n == (defaults[key] ?? 0) { continue }
            } else if trimmed.caseInsensitiveCompare("False") == .orderedSame || trimmed.isEmpty {
                continue
            } else if let neutral = neutralStrings[key], neutral.contains(trimmed) {
                continue
            }
            out.append("\(key)=\(trimmed)")
        }
        // Grain size and roughness only matter with grain on.
        if (xmp.number("GrainAmount") ?? 0) == 0 {
            out.removeAll { $0.hasPrefix("GrainSize=") || $0.hasPrefix("GrainFrequency=") }
        }
        // Without the conversion, a grey mix does nothing.
        if !xmp.flag("ConvertToGrayscale") {
            out.removeAll { $0.hasPrefix("GrayMixer") }
        }
        for (key, items) in xmp.lists where !used.contains(key) && !metadata.contains(key) {
            if let name = blockNames[key] {
                if !items.isEmpty { out.append(name) }
                continue
            }
            let points = xmp.points(key)
            if points.map({ MonotoneCurve.isIdentity($0) }) == false || (points == nil && !items.isEmpty) {
                out.append(key)
            }
        }
        for key in xmp.blocks where !used.contains(key) && !metadata.contains(key) {
            out.append(blockNames[key] ?? key)
        }
        return Array(Set(out)).sorted()
    }

    /// Keys that describe the preset rather than the look.
    static let metadata: Set<String> = [
        "Version", "ProcessVersion", "PresetType", "Cluster", "UUID", "SupportsAmount", "SupportsAmount2",
        "SupportsColor", "SupportsMonochrome", "SupportsHighDynamicRange", "SupportsNormalDynamicRange",
        "SupportsSceneReferredProfiles", "SupportsOutputReferred", "RequiresRGBTables", "CameraModelRestriction",
        "Copyright", "ContactInfo", "HasSettings", "HasCrop", "AlreadyApplied", "Name", "ShortName", "SortName",
        "Group", "Description", "ToneCurveName", "ToneCurveName2012", "ToneCurveName2012Red",
        "ToneCurveName2012Green", "ToneCurveName2012Blue", "OverrideLookVignette", "CompatibleVersion",
        "PresetAmount", "LookAmount", "CameraProfileDigest",
    ]

    /// Lightroom's own defaults for the settings it writes into every preset.
    static let defaults: [String: Double] = [
        "SharpenRadius": 1, "SharpenDetail": 25, "ColorNoiseReduction": 25, "ColorNoiseReductionDetail": 50,
        "ColorNoiseReductionSmoothness": 50, "LuminanceNoiseReductionDetail": 50, "GrainSize": 25,
        "GrainFrequency": 50, "PostCropVignetteMidpoint": 50, "PostCropVignetteFeather": 50,
        "PostCropVignetteStyle": 1, "DefringePurpleHueLo": 30, "DefringePurpleHueHi": 70,
        "DefringeGreenHueLo": 40, "DefringeGreenHueHi": 60, "PerspectiveScale": 100,
        "LensManualDistortionAmount": 0, "VignetteMidpoint": 50, "ShadowTint": 0, "CropRight": 1, "CropBottom": 1,
        "UprightFocalLength35mm": 35, "UprightPreview": 0, "UprightTransformCount": 6,
    ]

    /// String values that mean "nothing changed".
    static let neutralStrings: [String: Set<String>] = [
        "CameraProfile": ["Adobe Standard", "Adobe Color", "Embedded"],
        "ToneCurveName2012": ["Linear"],
        "LensProfileSetup": ["LensDefaults"],
    ]

    /// Readable names for nested blocks.
    static let blockNames: [String: String] = [
        "Look": "profile look (Look)", "MaskGroupBasedCorrections": "masks", "CircularGradientBasedCorrections": "radial masks",
        "GradientBasedCorrections": "linear masks", "PaintBasedCorrections": "brush masks", "RetouchInfo": "spot removal",
        "RedEyeInfo": "red eye", "PointColors": "point color", "LensBlur": "lens blur",
    ]
}
