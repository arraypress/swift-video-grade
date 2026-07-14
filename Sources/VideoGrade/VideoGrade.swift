//
//  VideoGrade.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// A color grade for the footage: an optional `.cube` LUT plus a full set of
/// tonal, color, and film-look adjustments. Pure data — serialize it in your
/// document; ``GradeFilter`` resolves it to Core Image at render time.
///
/// The one rule for a consumer: build the filter **once** with ``GradeFilter``
/// and use it for both the live `AVPlayerItem.videoComposition` and the offline
/// exporter, so preview and export match by construction.
public struct VideoGrade: Codable, Equatable, Sendable {

    /// A `.cube` LUT file, or `nil` for no LUT.
    public var lutURL: URL?

    /// LUT blend (`0` = off … `1` = full).
    public var lutIntensity: Double

    /// Exposure adjustment in EV (`0` = untouched).
    public var exposure: Double

    /// Brightness offset (`0` = untouched, `-1…1`).
    public var brightness: Double

    /// Contrast multiplier (`1` = untouched).
    public var contrast: Double

    /// Saturation multiplier (`1` = untouched, `0` = grayscale).
    public var saturation: Double

    /// Vibrance (`0` = untouched, `-1…1`) — saturation that protects skin.
    public var vibrance: Double

    /// White balance in Kelvin (`6500` = untouched).
    public var temperature: Double

    /// Green–magenta tint (`0` = untouched, `-100…100`).
    public var tint: Double

    /// Highlight recovery (`1` = untouched, toward `0` darkens highlights).
    public var highlights: Double

    /// Shadow lift (`0` = untouched, `-1…1`).
    public var shadows: Double

    /// Luminance sharpening (`0` = untouched, `0…2`).
    public var sharpness: Double

    /// Noise/skin smoothing (`0` = untouched, `0…1`).
    public var smoothing: Double

    /// Edge vignette (`0` = untouched, `0…2`).
    public var vignette: Double

    // MARK: - Film-look extensions (ported from FilterSpark, re-authored in
    // Core Image). All default to their neutral value so `isNeutral` still
    // holds for an untouched grade and old projects decode unchanged.

    /// Levels black point — lifts the shadows (`0` = untouched … `0.4`).
    public var levelsBlack: Double = 0
    /// Levels white point — pulls the highlights down (`1` = untouched … `0.6`).
    public var levelsWhite: Double = 1
    /// Levels midtone gamma (`1` = untouched; `<1` brightens, `>1` darkens).
    public var levelsGamma: Double = 1

    /// Matte "fade" — lifts blacks toward a washed film look (`0…1`).
    public var fade: Double = 0

    /// Film grain opacity (`0` = off … `1`). Animated per frame on export.
    public var grain: Double = 0

    /// Glow/bloom intensity — blurred highlights screened back (`0…1`).
    public var glow: Double = 0
    /// Glow spread in pixels (`0…40`).
    public var glowRadius: Double = 25

    /// Cinematic halation — a warm red/orange bloom that scatters around bright
    /// highlights (the film-base light-scatter look), `0…1`.
    public var halation: Double = 0
    /// Halation spread in pixels (`0…60`).
    public var halationRadius: Double = 30

    /// Filmic highlight rolloff — soft-clips the highlights so they don't hit
    /// hard digital white (`0…1`).
    public var filmicRolloff: Double = 0

    /// Animated warm light leak bleeding from a frame edge (`0…1`).
    public var lightLeak: Double = 0
    /// Which leak (position + color): 0 top-right amber, 1 left red,
    /// 2 bottom gold, 3 top-left magenta.
    public var lightLeakStyle: Int = 0

    /// Anamorphic horizontal blue streak flare off bright highlights (`0…1`).
    public var anamorphicFlare: Double = 0

    /// Old-film damage — animated vertical scratches + dust specks (`0…1`).
    public var filmDamage: Double = 0

    /// Lens chromatic aberration — R/B fringing that grows toward the edges
    /// (`0…1`).
    public var chromaticAberration: Double = 0

    /// Split-tone shadow tint (nil = none) and its strength (`0…1`).
    public var splitShadow: GradeColor?
    public var splitShadowAmount: Double = 0
    /// Split-tone highlight tint (nil = none) and its strength (`0…1`).
    public var splitHighlight: GradeColor?
    public var splitHighlightAmount: Double = 0

    /// Black & white conversion with a per-hue luminance mixer — brighten the
    /// red/orange bands to control skin tone in mono. Each band `-1…1`.
    public var blackAndWhite: Bool = false
    public var bwRed: Double = 0
    public var bwOrange: Double = 0
    public var bwYellow: Double = 0
    public var bwGreen: Double = 0
    public var bwAqua: Double = 0
    public var bwBlue: Double = 0
    public var bwPurple: Double = 0
    public var bwMagenta: Double = 0

    /// Skin-tone hue shift on the red band (`-1` cooler … `1` warmer).
    public var skinTone: Double = 0

    /// Interactive tone curves — control points in `0…1` (x = input, y =
    /// output). `nil` = identity. The master `curveRGB` applies to all three
    /// channels; the per-channel curves shape each one on top.
    public var curveRGB: [CGPoint]?
    public var curveRed: [CGPoint]?
    public var curveGreen: [CGPoint]?
    public var curveBlue: [CGPoint]?

    /// Full 12-band HSL — a hue/sat/lum shift per band (`nil` = identity). The
    /// pro color tool, exposed as an optional advanced mode.
    public var hslBands: [HSLBand]?

    /// Local-contrast "clarity" — midtone punch via a wide unsharp mask
    /// (`0` = untouched … `1`).
    public var clarity: Double = 0

    /// Luminance-adaptive depth: opens shadows and adds vibrance for pop
    /// (`-1…1`, `0` = untouched).
    public var brilliance: Double = 0

    /// Haze removal — contrast + saturation with a black deepen (`-1…1`,
    /// `0` = untouched; negative softens).
    public var dehaze: Double = 0

    public init(
        lutURL: URL? = nil,
        lutIntensity: Double = 1,
        exposure: Double = 0,
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        vibrance: Double = 0,
        temperature: Double = 6500,
        tint: Double = 0,
        highlights: Double = 1,
        shadows: Double = 0,
        sharpness: Double = 0,
        smoothing: Double = 0,
        vignette: Double = 0
    ) {
        self.lutURL = lutURL
        self.lutIntensity = lutIntensity
        self.exposure = exposure
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.vibrance = vibrance
        self.temperature = temperature
        self.tint = tint
        self.highlights = highlights
        self.shadows = shadows
        self.sharpness = sharpness
        self.smoothing = smoothing
        self.vignette = vignette
    }

    /// Tolerant decoding so grades from older project files keep opening as
    /// fields are added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lutURL = try container.decodeIfPresent(URL.self, forKey: .lutURL)
        lutIntensity = try container.decodeIfPresent(Double.self, forKey: .lutIntensity) ?? 1
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        vibrance = try container.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 6500
        tint = try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        highlights = try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 1
        shadows = try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        sharpness = try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0
        vignette = try container.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
        levelsBlack = try container.decodeIfPresent(Double.self, forKey: .levelsBlack) ?? 0
        levelsWhite = try container.decodeIfPresent(Double.self, forKey: .levelsWhite) ?? 1
        levelsGamma = try container.decodeIfPresent(Double.self, forKey: .levelsGamma) ?? 1
        fade = try container.decodeIfPresent(Double.self, forKey: .fade) ?? 0
        grain = try container.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        glow = try container.decodeIfPresent(Double.self, forKey: .glow) ?? 0
        glowRadius = try container.decodeIfPresent(Double.self, forKey: .glowRadius) ?? 25
        halation = try container.decodeIfPresent(Double.self, forKey: .halation) ?? 0
        halationRadius = try container.decodeIfPresent(Double.self, forKey: .halationRadius) ?? 30
        filmicRolloff = try container.decodeIfPresent(Double.self, forKey: .filmicRolloff) ?? 0
        lightLeak = try container.decodeIfPresent(Double.self, forKey: .lightLeak) ?? 0
        lightLeakStyle = try container.decodeIfPresent(Int.self, forKey: .lightLeakStyle) ?? 0
        anamorphicFlare = try container.decodeIfPresent(Double.self, forKey: .anamorphicFlare) ?? 0
        filmDamage = try container.decodeIfPresent(Double.self, forKey: .filmDamage) ?? 0
        chromaticAberration = try container.decodeIfPresent(Double.self, forKey: .chromaticAberration) ?? 0
        splitShadow = try container.decodeIfPresent(GradeColor.self, forKey: .splitShadow)
        splitShadowAmount = try container.decodeIfPresent(Double.self, forKey: .splitShadowAmount) ?? 0
        splitHighlight = try container.decodeIfPresent(GradeColor.self, forKey: .splitHighlight)
        splitHighlightAmount = try container.decodeIfPresent(Double.self, forKey: .splitHighlightAmount) ?? 0
        blackAndWhite = try container.decodeIfPresent(Bool.self, forKey: .blackAndWhite) ?? false
        bwRed = try container.decodeIfPresent(Double.self, forKey: .bwRed) ?? 0
        bwOrange = try container.decodeIfPresent(Double.self, forKey: .bwOrange) ?? 0
        bwYellow = try container.decodeIfPresent(Double.self, forKey: .bwYellow) ?? 0
        bwGreen = try container.decodeIfPresent(Double.self, forKey: .bwGreen) ?? 0
        bwAqua = try container.decodeIfPresent(Double.self, forKey: .bwAqua) ?? 0
        bwBlue = try container.decodeIfPresent(Double.self, forKey: .bwBlue) ?? 0
        bwPurple = try container.decodeIfPresent(Double.self, forKey: .bwPurple) ?? 0
        bwMagenta = try container.decodeIfPresent(Double.self, forKey: .bwMagenta) ?? 0
        skinTone = try container.decodeIfPresent(Double.self, forKey: .skinTone) ?? 0
        curveRGB = try container.decodeIfPresent([CGPoint].self, forKey: .curveRGB)
        curveRed = try container.decodeIfPresent([CGPoint].self, forKey: .curveRed)
        curveGreen = try container.decodeIfPresent([CGPoint].self, forKey: .curveGreen)
        curveBlue = try container.decodeIfPresent([CGPoint].self, forKey: .curveBlue)
        hslBands = try container.decodeIfPresent([HSLBand].self, forKey: .hslBands)
        clarity = try container.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        brilliance = try container.decodeIfPresent(Double.self, forKey: .brilliance) ?? 0
        dehaze = try container.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0
    }

    /// No grading at all.
    public static let neutral = VideoGrade()

    /// Whether this grade changes any pixel.
    public var isNeutral: Bool {
        self == .neutral
    }
}

/// One band of the 12-band HSL tool: a hue shift, saturation multiplier, and
/// luminance multiplier, all `-1…1` with `0` = identity.
public struct HSLBand: Codable, Equatable, Sendable {
    public var hue: Double
    public var sat: Double
    public var lum: Double

    public init(hue: Double = 0, sat: Double = 0, lum: Double = 0) {
        self.hue = hue
        self.sat = sat
        self.lum = lum
    }

    public var isIdentity: Bool { hue == 0 && sat == 0 && lum == 0 }
}

/// How the footage behaves at each cut boundary on export — makes filler
/// removal read as intentional editing instead of a raw jump cut.
public enum CutStyle: String, Codable, CaseIterable, Sendable {

    /// Plain jump cut.
    case none

    /// A quick dip through black across the cut.
    case dipToBlack

    /// A quick dip through white across the cut.
    case dipToWhite

    /// A subtle zoom punch-in that relaxes after the cut.
    case punchIn

    /// A horizontal motion-blur streak across the cut (whip pan).
    case whipPan

    /// A radial zoom-blur burst across the cut.
    case zoomBlur

    /// An RGB channel-split glitch across the cut.
    case glitch
}
