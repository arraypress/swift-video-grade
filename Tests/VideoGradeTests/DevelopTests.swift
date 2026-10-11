//
//  DevelopTests.swift
//  VideoGradeTests
//
//  Created by David Sherlock on 2026.
//
//  The Lightroom develop controls, measured on synthetic linear scenes.
//  Each test prints the number it asserts on, so the README's claims can
//  be checked against a run.
//

import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import VideoGrade

private func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
}

private func maxDifference(_ a: [Float], _ b: [Float]) -> Double {
    zip(a, b).reduce(0) { max($0, Double(abs($1.0 - $1.1))) }
}

/// Encoded (display) value of a linear channel.
private func enc(_ v: Double) -> Double { OkLab.encode(v) }

@Suite("Develop: compatibility")
struct DevelopCompatibilityTests {

    @Test("Grades written by 0.1.1 render exactly as 0.1.1 rendered them")
    func goldens() throws {
        for name in ["grade-0.1.1", "img-grade-0.1.1", "film-0.1.1"] {
            let grade = try JSONDecoder().decode(VideoGrade.self, from: fixture("\(name).json"))
            let golden = try fixture("\(name).bin").withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            let now = try SyntheticScene.graded(grade, SyntheticScene.golden())
            let diff = maxDifference(now, golden)
            print("GOLDEN \(name): max |Δ| = \(diff)")
            #expect(diff < 1e-5, "\(name) drifted by \(diff)")
        }
    }

    @Test("An img 0.6.0 recipe's grade decodes, and the new fields default to untouched")
    func oldRecipeDecodes() throws {
        let recipe = try JSONSerialization.jsonObject(with: fixture("img-recipe-0.6.0.json")) as? [String: Any]
        let operations = try #require(recipe?["operations"] as? [[String: Any]])
        let wrapped = try #require(operations.first?["grade"] as? [String: Any])
        let inner = try #require(wrapped["_0"])
        let data = try JSONSerialization.data(withJSONObject: inner)
        let grade = try JSONDecoder().decode(VideoGrade.self, from: data)
        #expect(grade.contrast == 1.2 && grade.blackAndWhite)
        #expect(grade.whites == 0 && grade.blacks == 0 && grade.texture == 0 && grade.hazeRemoval == 0)
        #expect(grade.toneCurve == nil && grade.colorMixer == nil && grade.colorGrading == nil && grade.monochromeMix == nil)
    }

    @Test("The new controls round-trip through JSON")
    func roundTrip() throws {
        var grade = VideoGrade()
        grade.whites = 0.2; grade.blacks = -0.3; grade.texture = 0.4; grade.hazeRemoval = -0.5
        grade.toneCurve = ToneCurve(darks: 0.3, master: [CGPoint(x: 0, y: 0.1), CGPoint(x: 1, y: 0.9)])
        var mixer = ColorMixer(); mixer.blue = MixerBand(hue: 0.2, saturation: -0.5, luminance: 0.1)
        grade.colorMixer = mixer
        grade.colorGrading = ColorGrading(shadows: GradingWheel(hue: 210, saturation: 0.3), blending: 0.7, balance: -0.2)
        grade.monochromeMix = MonochromeMix(red: 0.3, blue: -0.4)
        let back = try JSONDecoder().decode(VideoGrade.self, from: JSONEncoder().encode(grade))
        #expect(back == grade)
    }

    @Test("Every new control at its default changes no pixel, HDR and alpha included")
    func defaultsAreIdentity() throws {
        let scene = SyntheticScene.row([(0.2, 0.5, 0.9, 1), (4, 2, 0.5, 1), (0.1, 0.2, 0.3, 0.5), (0, 0, 0, 0)])
        var grade = VideoGrade()
        grade.toneCurve = ToneCurve()
        grade.colorMixer = ColorMixer()
        grade.colorGrading = ColorGrading()
        #expect(grade.isNeutral)
        #expect(DevelopCube.data(for: grade) == nil)
        let diff = maxDifference(try SyntheticScene.graded(grade, scene), SyntheticScene.render(scene))
        print("IDENTITY: max |Δ| at defaults = \(diff)")
        #expect(diff == 0)
    }
}

@Suite("Develop: tone")
struct DevelopToneTests {

    @Test("Curves never invert a tone, whatever points they are given")
    func curvesAreMonotone() throws {
        // Points out of order and doubling back, plus every region pushed hard.
        let wild = [CGPoint(x: 0.7, y: 0.9), CGPoint(x: 0, y: 0.1), CGPoint(x: 0.3, y: 0.7),
                    CGPoint(x: 0.5, y: 0.35), CGPoint(x: 1, y: 0.95)]
        var grade = VideoGrade()
        grade.toneCurve = ToneCurve(shadows: 1, darks: -1, lights: 1, highlights: -1,
                                    master: wild, red: wild.reversed(), blue: [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0)])
        // The math, densely.
        let curve = try #require(grade.toneCurve)
        let tables = try #require(ToneCurveMath.tables(curve))
        var worstMath = 0.0
        for table in tables { for i in 1..<table.count { worstMath = max(worstMath, table[i - 1] - table[i]) } }
        // And the rendered pipeline, on a grey ramp.
        let n = 256
        let ramp = SyntheticScene.image(width: n, height: 1) { x, _ in
            let v = OkLab.decode(Double(x) / Double(n - 1)); return (v, v, v, 1)
        }
        let out = try SyntheticScene.graded(grade, ramp)
        var worstRender = 0.0
        for c in 0..<3 { for i in 1..<n { worstRender = max(worstRender, Double(out[(i - 1) * 4 + c] - out[i * 4 + c])) } }
        print("CURVES: largest step down — math \(worstMath), rendered \(worstRender)")
        #expect(worstMath <= 1e-12)
        #expect(worstRender < 1e-4)
    }

    @Test("Whites move the upper tones, blacks the lower, mid-grey barely")
    func whitesAndBlacks() throws {
        let tones = [0.02, 0.18, 0.7]   // linear: shadow, middle grey, bright
        let scene = SyntheticScene.row(tones.map { ($0, $0, $0, 1) })
        let base = SyntheticScene.render(scene)
        var up = VideoGrade(); up.whites = 1
        var down = VideoGrade(); down.blacks = -1
        let w = try SyntheticScene.graded(up, scene), b = try SyntheticScene.graded(down, scene)
        let dW = (0..<3).map { enc(Double(w[$0 * 4])) - enc(Double(base[$0 * 4])) }
        let dB = (0..<3).map { enc(Double(b[$0 * 4])) - enc(Double(base[$0 * 4])) }
        print("WHITES +100 Δencoded shadow/grey/bright = \(dW); BLACKS −100 = \(dB)")
        #expect(dW[2] > 0.05 && dW[2] > dW[0] * 5)
        #expect(dB[0] < -0.005 && abs(dB[2]) < 1e-3)
        #expect(abs(dW[1]) < 0.01 && abs(dB[1]) < 0.01)
    }
}

@Suite("Develop: colour")
struct DevelopColourTests {

    /// Swatches every 15° of sRGB hue.
    private let hues = stride(from: 0.0, to: 360, by: 15).map { $0 }

    @Test("A mixer band leaves colours outside its neighbourhood alone")
    func mixerIsolation() throws {
        var mixer = ColorMixer()
        mixer.blue = MixerBand(hue: 1, saturation: -1, luminance: -1)
        var grade = VideoGrade(); grade.colorMixer = mixer
        let scene = SyntheticScene.row(hues.map { SyntheticScene.hue($0) })
        let before = SyntheticScene.render(scene), after = try SyntheticScene.graded(grade, scene)
        var outside = 0.0, blue = 0.0
        for (i, h) in hues.enumerated() {
            let d = (0..<3).map { abs(enc(Double(after[i * 4 + $0])) - enc(Double(before[i * 4 + $0]))) }.max() ?? 0
            // Blue's neighbours are aqua (180°) and purple (270°); beyond them weights are zero.
            if h <= 165 || h >= 285 { outside = max(outside, d) }
            if h == 225 { blue = d }
        }
        print("MIXER blue band: largest change outside 180–270° = \(outside); change at 225° = \(blue)")
        #expect(outside < 0.01)
        #expect(blue > 0.1)
    }

    @Test("Colour grading moves only its tonal range")
    func gradingRanges() throws {
        let n = 64
        let ramp = SyntheticScene.image(width: n, height: 1) { x, _ in
            let v = OkLab.decode(Double(x) / Double(n - 1)); return (v, v, v, 1)
        }
        let before = SyntheticScene.render(ramp)
        func spread(_ px: [Float], _ i: Int) -> Double {
            let c = (0..<3).map { enc(Double(px[i * 4 + $0])) }
            return (c.max() ?? 0) - (c.min() ?? 0)
        }
        func lightness(_ i: Int) -> Double {
            let c = SyntheticScene.colour(before, i); return OkLab.fromLinear(c.0, c.1, c.2).0
        }
        var shadows = VideoGrade(); shadows.colorGrading = ColorGrading(shadows: GradingWheel(hue: 210, saturation: 1))
        var highs = VideoGrade(); highs.colorGrading = ColorGrading(highlights: GradingWheel(hue: 40, saturation: 1))
        let s = try SyntheticScene.graded(shadows, ramp), h = try SyntheticScene.graded(highs, ramp)
        var sOutside = 0.0, sInside = 0.0, hOutside = 0.0, hInside = 0.0
        for i in 0..<n {
            let L = lightness(i)
            // With blending 50 and balance 0: shadows end at L 0.6, highlights start at L 0.4.
            if L >= 0.65 { sOutside = max(sOutside, spread(s, i)) }
            if L > 0.05 && L <= 0.3 { sInside = max(sInside, spread(s, i)) }
            if L <= 0.35 { hOutside = max(hOutside, spread(h, i)) }
            if L >= 0.75 { hInside = max(hInside, spread(h, i)) }
        }
        print("GRADING tint spread — shadows wheel: in range \(sInside), above L 0.65 \(sOutside); highlights wheel: in range \(hInside), below L 0.35 \(hOutside)")
        #expect(sOutside < 0.005 && sInside > 0.03)
        #expect(hOutside < 0.005 && hInside > 0.03)
    }

    @Test("The black & white mix makes grey, and a band lightens its colours")
    func monochrome() throws {
        let scene = SyntheticScene.row(hues.map { SyntheticScene.hue($0) })
        var plain = VideoGrade(); plain.monochromeMix = MonochromeMix()
        var bluer = VideoGrade(); bluer.monochromeMix = MonochromeMix(blue: 1)
        let p = try SyntheticScene.graded(plain, scene), b = try SyntheticScene.graded(bluer, scene)
        var chroma = 0.0
        for i in 0..<hues.count {
            let c = (0..<3).map { enc(Double(p[i * 4 + $0])) }
            chroma = max(chroma, (c.max() ?? 0) - (c.min() ?? 0))
        }
        let blueIndex = hues.firstIndex(of: 225)!, redIndex = hues.firstIndex(of: 0)!
        let lift = enc(Double(b[blueIndex * 4])) - enc(Double(p[blueIndex * 4]))
        let redLift = enc(Double(b[redIndex * 4])) - enc(Double(p[redIndex * 4]))
        print("MONO: largest channel spread \(chroma); blue +100 lifts blue by \(lift), red by \(redLift)")
        #expect(chroma < 0.01)
        #expect(lift > 0.05 && abs(redLift) < 0.005)
    }
}

@Suite("Develop: range and alpha")
struct DevelopRangeTests {

    /// Everything on at once, moderately.
    private var everything: VideoGrade {
        var g = VideoGrade()
        g.whites = 0.3; g.blacks = -0.2; g.texture = 0.4; g.hazeRemoval = 0.4
        g.toneCurve = ToneCurve(lights: 0.3)
        var m = ColorMixer(); m.blue = MixerBand(saturation: -0.5); g.colorMixer = m
        g.colorGrading = ColorGrading(midtones: GradingWheel(hue: 30, saturation: 0.2))
        return g
    }

    @Test("Values above 1 survive every new stage")
    func hdrSurvives() throws {
        let scene = SyntheticScene.image(width: 16, height: 16) { x, _ in x < 8 ? (4, 4, 4, 1) : (0.2, 0.3, 0.4, 1) }
        var curveOnly = VideoGrade(); curveOnly.toneCurve = ToneCurve(lights: 0.3)
        let c = try SyntheticScene.graded(curveOnly, scene)
        let e = try SyntheticScene.graded(everything, scene)
        let hazeOnly = try SyntheticScene.graded({ var g = VideoGrade(); g.hazeRemoval = 0.5; return g }(), scene)
        let texOnly = try SyntheticScene.graded({ var g = VideoGrade(); g.texture = -0.8; return g }(), scene)
        print("HDR 4.0 through: tone curve \(c[0]), everything \(e[0]), dehaze \(hazeOnly[0]), texture −80 \(texOnly[0])")
        #expect(abs(Double(c[0]) - 4) < 0.25)
        for v in [e[0], hazeOnly[0], texOnly[0]] { #expect(v > 1.5) }
    }

    @Test("Transparent pixels stay transparent and alpha is kept")
    func alphaKept() throws {
        let scene = SyntheticScene.image(width: 24, height: 24) { x, y in
            x < 8 ? (0, 0, 0, 0) : x < 16 ? (0.3, 0.2, 0.1, 0.5) : (0.1 + 0.02 * Double(y), 0.4, 0.6, 1)
        }
        let out = try SyntheticScene.graded(everything, scene)
        var clear = 0.0, alphaDrift = 0.0
        for y in 0..<24 {
            for x in 0..<24 {
                let i = (y * 24 + x) * 4
                if x < 8 { clear = max(clear, (0..<4).map { Double(abs(out[i + $0])) }.max() ?? 0) }
                let expected: Float = x < 8 ? 0 : x < 16 ? 0.5 : 1
                alphaDrift = max(alphaDrift, Double(abs(out[i + 3] - expected)))
            }
        }
        print("ALPHA: largest component in transparent pixels \(clear); largest alpha drift \(alphaDrift)")
        #expect(clear < 1e-6)
        #expect(alphaDrift < 1e-3)
    }
}

@Suite("Develop: dehaze and detail")
struct DevelopSpatialTests {

    /// A known scene J under haze of known transmission and airlight:
    /// I = J·t + A·(1 − t). A sky band at the top is almost pure veil,
    /// as in a real hazy photograph, which is where the airlight is read.
    private static let side = 128
    private static let airlight = 0.8
    private static func clear(_ x: Int, _ y: Int) -> (Double, Double, Double) {
        // Saturated tiles: every one has a channel near zero (the dark-channel prior).
        let palette: [(Double, Double, Double)] = [(0.6, 0.15, 0.02), (0.02, 0.4, 0.1), (0.05, 0.1, 0.5),
                                                   (0.5, 0.45, 0.02), (0.02, 0.3, 0.35), (0.4, 0.02, 0.3)]
        return palette[((x / 16) + (y / 16) * 3) % palette.count]
    }
    private static func transmission(_ x: Int, _ y: Int) -> Double {
        y >= side - 16 ? 0.02 : 0.35 + 0.55 * Double(x) / Double(side - 1)
    }
    private static func hazy() -> CIImage {
        SyntheticScene.image(width: side, height: side) { x, y in
            let j = clear(x, y), t = transmission(x, y)
            return (j.0 * t + airlight * (1 - t), j.1 * t + airlight * (1 - t), j.2 * t + airlight * (1 - t), 1)
        }
    }

    /// Mean absolute error against the clear scene, sky excluded.
    private static func error(_ px: [Float]) -> Double {
        var sum = 0.0, count = 0.0
        // Rendered rows come back in the order they were generated; skip
        // the sky band and the tile edges.
        for y in 0..<(side - 16) {
            for x in 0..<side where x % 16 > 2 && x % 16 < 13 && y % 16 > 2 && y % 16 < 13 {
                let j = clear(x, y), i = (y * side + x) * 4
                sum += abs(Double(px[i]) - j.0) + abs(Double(px[i + 1]) - j.1) + abs(Double(px[i + 2]) - j.2)
                count += 3
            }
        }
        return sum / count
    }

    @Test("Dehaze recovers a synthetic haze of known transmission and airlight")
    func dehazeRecovers() throws {
        let scene = Self.hazy()
        let before = Self.error(SyntheticScene.render(scene))
        var grade = VideoGrade(); grade.hazeRemoval = 1
        let after = Self.error(try SyntheticScene.graded(grade, scene))
        // The same job in a gamma-encoded working space, as `img` renders.
        let encoded = Self.error(try SyntheticScene.graded(grade, scene, working: SyntheticScene.sRGB))
        var adding = VideoGrade(); adding.hazeRemoval = -1
        let added = Self.error(try SyntheticScene.graded(adding, scene))
        print("DEHAZE mean |J − ·| (linear): hazy \(before) → dehazed \(after) (sRGB working: \(encoded)); −100 adds haze: \(added)")
        #expect(after < before * 0.5)
        #expect(abs(encoded - after) < 0.01)
        #expect(added > before)
    }

    /// Mean absolute difference between neighbouring pixels in a region.
    private static func roughness(_ px: [Float], width: Int, rows: Range<Int>, columns: Range<Int>) -> Double {
        var sum = 0.0, n = 0.0
        for y in rows { for x in columns.dropLast() {
            sum += abs(Double(px[(y * width + x + 1) * 4 + 1] - px[(y * width + x) * 4 + 1])); n += 1
        } }
        return sum / n
    }

    @Test("Texture scales fine detail and leaves flat areas alone")
    func texture() throws {
        let w = 400, h = 40
        // Left: a 2-px checker (fine detail). Right: flat.
        let scene = SyntheticScene.image(width: w, height: h) { x, y in
            x < 200 ? ((x / 2 + y / 2) % 2 == 0 ? (0.3, 0.3, 0.3, 1) : (0.2, 0.2, 0.2, 1)) : (0.25, 0.25, 0.25, 1)
        }
        let base = SyntheticScene.render(scene)
        var more = VideoGrade(); more.texture = 1
        var less = VideoGrade(); less.texture = -1
        let m = try SyntheticScene.graded(more, scene), l = try SyntheticScene.graded(less, scene)
        let rough = { (px: [Float]) in Self.roughness(px, width: w, rows: 10..<30, columns: 20..<180) }
        let flat = (0..<w * h).filter { $0 % w > 230 && $0 % w < 370 }
            .map { Double(abs(m[$0 * 4 + 1] - base[$0 * 4 + 1])) }.max() ?? 0
        print("TEXTURE detail: base \(rough(base)), +100 \(rough(m)), −100 \(rough(l)); flat area change \(flat)")
        #expect(rough(m) > rough(base) * 1.2)
        #expect(rough(l) < rough(base) * 0.8)
        #expect(flat < 1e-4)
    }

    @Test("Negative clarity softens mid-scale contrast")
    func negativeClarity() throws {
        let w = 240
        let scene = SyntheticScene.image(width: w, height: 20) { x, _ in
            (x / 20) % 2 == 0 ? (0.4, 0.4, 0.4, 1) : (0.1, 0.1, 0.1, 1)
        }
        var grade = VideoGrade(); grade.clarity = -1
        let base = SyntheticScene.render(scene), soft = try SyntheticScene.graded(grade, scene)
        let edge = { (px: [Float]) in Self.roughness(px, width: w, rows: 5..<15, columns: 30..<210) }
        print("CLARITY −100 edge energy: \(edge(base)) → \(edge(soft))")
        #expect(edge(soft) < edge(base) * 0.8)
    }
}
