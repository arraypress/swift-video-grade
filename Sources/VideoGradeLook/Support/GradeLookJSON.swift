//
//  GradeLookJSON.swift
//  VideoGradeLook
//
//  Created by David Sherlock on 2026.
//
//  How a grade is written in a recipe, and read back: the settings that
//  differ from an untouched grade, by the engine's names in snake_case
//  (`lut_intensity`, `curve_rgb`, `tone_curve.shadow_split`), with the LUT
//  as a path. Reading goes through VideoGrade's own tolerant decoding, so
//  a field left out is untouched; the strict key check (RecipeKit) runs
//  first, so a misspelt one is refused, never ignored.
//
//  img and vid each held a copy of this file; design, the third user, made
//  it this library.
//

import Foundation
import RecipeKit
import VideoGrade

public enum GradeLookJSON {

    // MARK: Names

    /// The grade's settings by the engine's names, in the order a bare
    /// `--set` name is looked for. `lutURL` is not here: the LUT is `lut`.
    public static let engineKeys: [String] = [
        "lutIntensity", "exposure", "brightness", "contrast", "saturation", "vibrance", "temperature", "tint",
        "highlights", "shadows", "whites", "blacks", "clarity", "texture", "hazeRemoval", "dehaze", "brilliance",
        "sharpness", "smoothing", "vignette", "grain", "fade", "levelsBlack", "levelsWhite", "levelsGamma",
        "glow", "glowRadius", "halation", "halationRadius", "filmicRolloff", "lightLeak", "lightLeakStyle",
        "anamorphicFlare", "filmDamage", "chromaticAberration", "splitShadow", "splitShadowAmount",
        "splitHighlight", "splitHighlightAmount", "blackAndWhite", "bwRed", "bwOrange", "bwYellow", "bwGreen",
        "bwAqua", "bwBlue", "bwPurple", "bwMagenta", "skinTone", "curveRGB", "curveRed", "curveGreen",
        "curveBlue", "hslBands", "toneCurve", "colorMixer", "colorGrading", "monochromeMix",
    ]

    /// The keys a recipe's grade section may hold.
    public static let keys: [String] = ["lut"] + engineKeys.map(snake)

    /// Keys inside the grade's objects that are not one word.
    static let nestedEngineKeys = ["shadowSplit", "midtoneSplit", "highlightSplit"]

    static let bands = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"]
    static let wheels = ["shadows", "midtones", "highlights", "global"]
    static let hsl = ["hue", "saturation", "luminance"]
    static let toneCurveKeys = ["shadows", "darks", "lights", "highlights", "shadow_split", "midtone_split",
                                "highlight_split", "master", "red", "green", "blue"]

    /// `curveRGB` → `curve_rgb`, `lutIntensity` → `lut_intensity`.
    public static func snake(_ name: String) -> String {
        let characters = Array(name)
        var out = ""
        for (index, character) in characters.enumerated() {
            if character.isUppercase, index > 0 {
                let previous = characters[index - 1]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && next?.isLowercase == true) {
                    out += "_"
                }
            }
            out += character.lowercased()
        }
        return out
    }

    /// File names back to the engine's.
    static let engineName: [String: String] = Dictionary(
        uniqueKeysWithValues: (engineKeys + nestedEngineKeys).map { (snake($0), $0) })

    /// `value` with every object key renamed by `rename`.
    static func renamed(_ value: JSONValue, _ rename: (String) -> String) -> JSONValue {
        switch value {
        case .object(let object):
            .object(Dictionary(uniqueKeysWithValues: object.map { (rename($0.key), renamed($0.value, rename)) }))
        case .array(let items): .array(items.map { renamed($0, rename) })
        default: value
        }
    }

    // MARK: Writing

    /// The grade section for `look`: the settings that differ from an
    /// untouched grade, snake_case, and the LUT's path.
    static func object(for look: GradeLook) throws -> [String: JSONValue] {
        var bare = look.grade
        bare.lutURL = nil
        let all = try engineObject(bare), untouched = try engineObject(VideoGrade())
        // Inside the panels (tone curve, mixer, grading, mono mix) the same
        // rule: only what differs from the panel untouched. A panel that is
        // there but untouched stays as {} — being there can matter.
        var panels = VideoGrade()
        panels.toneCurve = ToneCurve()
        panels.colorMixer = ColorMixer()
        panels.colorGrading = ColorGrading()
        panels.monochromeMix = MonochromeMix()
        let panelDefaults = try engineObject(panels)
        var out: [String: JSONValue] = [:]
        for (key, value) in all where untouched[key] != value {
            out[snake(key)] = renamed(pruned(value, against: panelDefaults[key]), snake)
        }
        if let lut = look.lut { out["lut"] = .string(lut) }
        return out
    }

    /// `value` without the keys that equal `base`'s, all the way down.
    static func pruned(_ value: JSONValue, against base: JSONValue?) -> JSONValue {
        guard case .object(let object) = value, case .object(let defaults)? = base else { return value }
        var kept: [String: JSONValue] = [:]
        for (key, item) in object where defaults[key] != item { kept[key] = pruned(item, against: defaults[key]) }
        return .object(kept)
    }

    /// A grade as VideoGrade itself writes it.
    static func engineObject(_ grade: VideoGrade) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(grade))
    }

    // MARK: Reading

    /// The grade and LUT path in a grade section. A wrong type is reported
    /// at its path in the file (`grade.tone_curve.shadows`).
    static func decode(from decoder: any Decoder) throws -> (VideoGrade, String?) {
        var object = try [String: JSONValue](from: decoder)
        var lut: String?
        switch object.removeValue(forKey: "lut") {
        case nil, .null?: lut = nil
        case .string(let path)?: lut = path
        default:
            throw DecodingError.typeMismatch(String.self, .init(codingPath: decoder.codingPath + [Key("lut")],
                                                                debugDescription: "lut is a path"))
        }
        let engine = renamed(.object(object)) { engineName[$0] ?? $0 }
        do {
            var grade = try JSONDecoder().decode(VideoGrade.self, from: JSONEncoder().encode(engine))
            grade.lutURL = nil
            return (grade, lut)
        } catch let error as DecodingError {
            throw relocated(error, under: decoder.codingPath)
        }
    }

    /// A decoding error from the engine's names, moved to its place in the
    /// file and named the file's way.
    static func relocated(_ error: DecodingError, under base: [any CodingKey]) -> DecodingError {
        func moved(_ context: DecodingError.Context) -> DecodingError.Context {
            .init(codingPath: base + context.codingPath.map { $0.intValue.map(Key.init(index:)) ?? Key(snake($0.stringValue)) },
                  debugDescription: context.debugDescription, underlyingError: context.underlyingError)
        }
        switch error {
        case .typeMismatch(let type, let context): return .typeMismatch(type, moved(context))
        case .valueNotFound(let type, let context): return .valueNotFound(type, moved(context))
        case .keyNotFound(let key, let context): return .keyNotFound(Key(snake(key.stringValue)), moved(context))
        case .dataCorrupted(let context): return .dataCorrupted(moved(context))
        @unknown default: return error
        }
    }

    /// A coding key by name or index.
    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(_ name: String) { stringValue = name }
        init(index: Int) { stringValue = String(index); intValue = index }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.init(index: intValue) }
    }

    // MARK: The strict shape

    /// The grade's objects, for a ``RecipeFormat``, under `prefix` (`grade`).
    public static func sections(under prefix: String) -> [RecipeFormat.Section] {
        [.init(prefix, keys: keys),
         .init(prefix + ".split_shadow", keys: ["red", "green", "blue", "alpha"]),
         .init(prefix + ".split_highlight", keys: ["red", "green", "blue", "alpha"]),
         .init(prefix + ".tone_curve", keys: toneCurveKeys),
         .init(prefix + ".color_mixer", keys: bands),
         .init(prefix + ".color_grading", keys: wheels + ["blending", "balance"]),
         .init(prefix + ".monochrome_mix", keys: bands)]
        + bands.map { .init(prefix + ".color_mixer." + $0, keys: hsl) }
        + wheels.map { .init(prefix + ".color_grading." + $0, keys: hsl) }
    }

    /// What a section list cannot say: each `hsl_bands` entry is an object
    /// of `hue`, `sat` and `lum`.
    public static func check(_ grade: Any?, at prefix: String) throws(RecipeError) {
        guard let bands = (grade as? [String: Any])?["hsl_bands"] as? [Any] else { return }
        for (index, band) in bands.enumerated() {
            guard let object = band as? [String: Any] else { throw RecipeError("\(prefix).hsl_bands.\(index) is not an object") }
            try RecipeJSON.unknownKeys(in: object, known: ["hue", "sat", "lum"], at: "\(prefix).hsl_bands.\(index).")
        }
    }

    // MARK: --set

    /// What each grade field holds, by its path under `prefix`, in the order
    /// a bare name is looked for.
    public static func kinds(under prefix: String) -> [(String, FieldKind)] {
        var table: [(String, FieldKind)] = [(prefix + ".lut", .custom { text, _ in
            URL(fileURLWithPath: RecipePaths.expanded(text)).standardizedFileURL.path
        })]
        for key in engineKeys.map(snake) {
            let kind: FieldKind = switch key {
            case "black_and_white": .bool
            case "light_leak_style": .integer(0...3)
            case "split_shadow", "split_highlight": .custom(color)
            case "curve_rgb", "curve_red", "curve_green", "curve_blue", "hsl_bands",
                 "tone_curve", "color_mixer", "color_grading", "monochrome_mix": .custom(json)
            default: .number
            }
            table.append((prefix + "." + key, kind))
        }
        for key in toneCurveKeys {
            table.append(("\(prefix).tone_curve.\(key)", ["master", "red", "green", "blue"].contains(key) ? .custom(json) : .number))
        }
        for band in bands {
            for part in hsl { table.append(("\(prefix).color_mixer.\(band).\(part)", .number)) }
        }
        for wheel in wheels {
            for part in hsl { table.append(("\(prefix).color_grading.\(wheel).\(part)", .number)) }
        }
        table += [("\(prefix).color_grading.blending", .number), ("\(prefix).color_grading.balance", .number)]
        table += bands.map { ("\(prefix).monochrome_mix.\($0)", .number) }
        return table
    }

    /// A JSON value as typed: `[[0,0],[0.5,0.6],[1,1]]`.
    @Sendable static func json(_ text: String, _ name: String) throws(RecipeError) -> Any {
        guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed) else {
            throw RecipeError("\(name) takes JSON, e.g. [[0,0],[0.5,0.6],[1,1]]; not \(text)")
        }
        return value
    }

    /// A tint: `#RRGGBB`, or a JSON object of red, green, blue and alpha.
    @Sendable static func color(_ text: String, _ name: String) throws(RecipeError) -> Any {
        if let color = GradeColor(hex: text) {
            return ["red": color.red, "green": color.green, "blue": color.blue, "alpha": color.alpha]
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw RecipeError("\(name) is a colour, #RRGGBB; not \(text)")
        }
        return object
    }
}
