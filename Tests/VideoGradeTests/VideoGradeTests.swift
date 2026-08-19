//
//  VideoGradeTests.swift
//  VideoGradeTests
//
//  Created by David Sherlock on 2026.
//

import CoreImage
import Foundation
import Testing
@testable import VideoGrade

private func roundTrip(_ grade: VideoGrade) throws -> VideoGrade {
    let data = try JSONEncoder().encode(grade)
    return try JSONDecoder().decode(VideoGrade.self, from: data)
}

private func renderPixel(_ image: CIImage) -> (r: Double, g: Double, b: Double) {
    var data = [UInt8](repeating: 0, count: 4)
    CIContext().render(
        image, toBitmap: &data, rowBytes: 4,
        bounds: CGRect(x: 4, y: 4, width: 1, height: 1),
        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
    )
    return (Double(data[0]) / 255, Double(data[1]) / 255, Double(data[2]) / 255)
}

private func imageBytes(_ image: CIImage, side: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: side * side * 4)
    CIContext().render(
        image, toBitmap: &data, rowBytes: side * 4,
        bounds: CGRect(x: 0, y: 0, width: side, height: side),
        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
    )
    return data
}

@Suite("Video grade")
struct GradeTests {

    @Test("Cube parser reads a valid 2-point LUT")
    func cubeParsing() throws {
        let cube = """
        TITLE "test"
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """
        let parsed = try CubeParser.parse(cube)
        #expect(parsed.dimension == 2)
        #expect(parsed.data.count == 2 * 2 * 2 * 4 * MemoryLayout<Float>.size)
    }

    @Test("Cube parser rejects malformed files")
    func cubeErrors() {
        #expect(throws: CubeParser.CubeError.self) { try CubeParser.parse("no size here\n0 0 0") }
        #expect(throws: CubeParser.CubeError.self) { try CubeParser.parse("LUT_3D_SIZE 2\n0 0 0") }
    }

    @Test("A corrupt size line is refused before it allocates")
    func cubeSizeBound() {
        // The declared size is untrusted input: 100000 would mean petabytes
        // of floats. The refusal has to come from reading the header, not
        // from the allocator giving up.
        #expect(throws: CubeParser.CubeError.unsupportedSize(100_000)) {
            try CubeParser.parse("LUT_3D_SIZE 100000\n0 0 0")
        }
        #expect(throws: CubeParser.CubeError.unsupportedSize(129)) {
            try CubeParser.parse("LUT_3D_SIZE 129\n0 0 0")
        }
    }

    @Test("Inert settings do not make a grade non-neutral")
    func semanticNeutrality() throws {
        // Each of these carries a value that grades nothing, because the
        // amount that would apply it is off.
        var radius = VideoGrade(); radius.glowRadius = 8
        #expect(radius.isNeutral)
        var leak = VideoGrade(); leak.lightLeakStyle = 3
        #expect(leak.isNeutral)
        var tint = VideoGrade(); tint.splitShadow = .blue   // amount stays 0
        #expect(tint.isNeutral)
        var mixer = VideoGrade(); mixer.bwRed = 1           // blackAndWhite stays false
        #expect(mixer.isNeutral)
        var flat = VideoGrade(); flat.curveRGB = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]
        #expect(flat.isNeutral)
        var short = VideoGrade(); short.hslBands = [HSLBand(hue: 1)]  // cube needs 12
        #expect(short.isNeutral)

        // And the pixels agree: the inert grade renders the same bytes.
        let base = CIImage(color: CIColor(red: 0.6, green: 0.4, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        #expect(imageBytes(try GradeFilter(grade: tint).apply(base), side: 8)
                == imageBytes(try GradeFilter(grade: .neutral).apply(base), side: 8))

        // The driver switching on still reads as active.
        var live = tint; live.splitShadowAmount = 0.4
        #expect(!live.isNeutral)
    }

    @Test("An absurd temperature is clamped, not handed to Core Image")
    func temperatureClamp() throws {
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        // Past 13000K the naive reflection goes to zero Kelvin and below —
        // not a color. Clamped, it stays a very warm white balance.
        var scorching = VideoGrade(); scorching.temperature = 20_000
        let hot = renderPixel(try GradeFilter(grade: scorching).apply(gray))
        #expect(hot.r > hot.b)
        var freezing = VideoGrade(); freezing.temperature = 1
        let cold = renderPixel(try GradeFilter(grade: freezing).apply(gray))
        #expect(cold.b > cold.r)
    }

    @Test("Neutral grade is detected; adjusted grades apply")
    func neutrality() throws {
        #expect(VideoGrade().isNeutral)
        var grade = VideoGrade()
        grade.brightness = 0.2
        #expect(!grade.isNeutral)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        #expect(try GradeFilter(grade: grade).apply(input).extent == input.extent)
    }

    @Test("Grade round-trips, including split-tone GradeColor and new fields")
    func serialization() throws {
        var grade = VideoGrade()
        grade.saturation = 1.3
        grade.vignette = 0.8
        grade.levelsBlack = 0.1
        grade.grain = 0.3
        grade.blackAndWhite = true
        grade.bwRed = 0.5
        grade.skinTone = -0.3
        grade.splitShadow = .blue
        grade.splitShadowAmount = 0.4
        grade.splitHighlight = .orange
        grade.splitHighlightAmount = 0.6
        grade.curveRGB = [CGPoint(x: 0, y: 0.2), CGPoint(x: 0.5, y: 0.4), CGPoint(x: 1, y: 0.9)]
        var bands = Array(repeating: HSLBand(), count: 12)
        bands[0] = HSLBand(hue: 0.4, sat: 0.3, lum: 0.2)
        grade.hslBands = bands
        #expect(try roundTrip(grade) == grade)
    }

    /// The backward-compat guarantee: a grade serialized when split-tone was a
    /// CaptionKit `StyleColor` (`{red,green,blue,alpha}`) still decodes here.
    @Test("Legacy StyleColor-shaped split-tone decodes into GradeColor")
    func legacyColorShape() throws {
        let json = #"{"splitShadow":{"red":0.04,"green":0.52,"blue":1,"alpha":1},"splitShadowAmount":1}"#
        let grade = try JSONDecoder().decode(VideoGrade.self, from: Data(json.utf8))
        #expect(grade.splitShadow == .blue)
        #expect(grade.splitShadowAmount == 1)
    }

    @Test("Black & white converts a colored frame to gray")
    func blackAndWhite() throws {
        var grade = VideoGrade()
        grade.blackAndWhite = true
        let red = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let px = renderPixel(try GradeFilter(grade: grade).apply(red))
        #expect(abs(px.r - px.g) < 0.02 && abs(px.g - px.b) < 0.02)
    }

    @Test("Each film-look stage changes pixels")
    func filmLookStages() throws {
        let base = CIImage(color: CIColor(red: 0.75, green: 0.35, blue: 0.25))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let neutral = renderPixel(try GradeFilter(grade: .neutral).apply(base))
        func changes(_ mutate: (inout VideoGrade) -> Void) throws -> Bool {
            var grade = VideoGrade(); mutate(&grade)
            let px = renderPixel(try GradeFilter(grade: grade).apply(base))
            return abs(px.r - neutral.r) + abs(px.g - neutral.g) + abs(px.b - neutral.b) > 0.01
        }
        #expect(try changes { $0.levelsBlack = 0.2 })
        #expect(try changes { $0.levelsGamma = 2 })
        #expect(try changes { $0.fade = 0.8 })
        #expect(try changes { $0.glow = 1; $0.glowRadius = 8 })
        #expect(try changes { $0.skinTone = 1 })
        #expect(try changes { $0.splitShadow = .blue; $0.splitShadowAmount = 1 })
        #expect(try changes { $0.brilliance = 1 })
        #expect(try changes { $0.dehaze = 1 })
    }

    @Test("Tone curves brighten midtones when the black point lifts")
    func toneCurves() throws {
        var lifted = VideoGrade()
        lifted.curveRGB = [CGPoint(x: 0, y: 0.35), CGPoint(x: 1, y: 1)]
        #expect(!lifted.isNeutral)
        let base = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let neutral = renderPixel(try GradeFilter(grade: .neutral).apply(base))
        let curved = renderPixel(try GradeFilter(grade: lifted).apply(base))
        #expect(curved.r - neutral.r > 0.05)
    }

    @Test("12-band HSL shifts a targeted hue")
    func hslBands() throws {
        var grade = VideoGrade()
        var desatRed = Array(repeating: HSLBand(), count: 12)
        desatRed[0] = HSLBand(hue: 0, sat: -1, lum: 0)
        grade.hslBands = desatRed
        #expect(!grade.isNeutral)
        let red = CIImage(color: CIColor(red: 0.85, green: 0.15, blue: 0.15))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let before = renderPixel(try GradeFilter(grade: .neutral).apply(red))
        let after = renderPixel(try GradeFilter(grade: grade).apply(red))
        #expect(abs(after.r - before.r) + abs(after.g - before.g) > 0.05)
    }

    @Test("Halation blooms bright highlights and reads warm")
    func halation() throws {
        var grade = VideoGrade()
        grade.halation = 1
        grade.halationRadius = 8
        let bright = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.95))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let neutral = renderPixel(try GradeFilter(grade: .neutral).apply(bright))
        let bloomed = renderPixel(try GradeFilter(grade: grade).apply(bright))
        #expect(bloomed.r >= neutral.r)
        #expect(bloomed.r - bloomed.b > 0.01)
    }

    @Test("Each cinematic effect alters the frame")
    func cinematicEffects() throws {
        let side = 24
        let bright = CIImage(color: CIColor(red: 0.9, green: 0.85, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        let base = imageBytes(try GradeFilter(grade: .neutral).apply(bright, time: 1), side: side)
        func differs(_ mutate: (inout VideoGrade) -> Void) throws -> Bool {
            var grade = VideoGrade(); mutate(&grade)
            return imageBytes(try GradeFilter(grade: grade).apply(bright, time: 1), side: side) != base
        }
        #expect(try differs { $0.filmicRolloff = 1 })
        #expect(try differs { $0.anamorphicFlare = 1 })
        #expect(try differs { $0.lightLeak = 1 })
        #expect(try differs { $0.filmDamage = 1 })
    }

    @Test("Higher temperature warms the frame, lower cools it")
    func temperatureDirection() throws {
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        var warm = VideoGrade(); warm.temperature = 9000
        #expect(renderPixel(try GradeFilter(grade: warm).apply(gray)).r > renderPixel(try GradeFilter(grade: warm).apply(gray)).b)
        var cool = VideoGrade(); cool.temperature = 4000
        let cpx = renderPixel(try GradeFilter(grade: cool).apply(gray))
        #expect(cpx.b > cpx.r)
    }

    @Test("Positive tint pushes toward magenta, negative toward green")
    func tintDirection() throws {
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        var magenta = VideoGrade(); magenta.tint = 100
        let mpx = renderPixel(try GradeFilter(grade: magenta).apply(gray))
        #expect((mpx.r + mpx.b) / 2 > mpx.g)
        var green = VideoGrade(); green.tint = -100
        let gpx = renderPixel(try GradeFilter(grade: green).apply(gray))
        #expect(gpx.g > (gpx.r + gpx.b) / 2)
    }

    @Test("Chromatic aberration keeps a flat frame's brightness (no washout)")
    func chromaticNoWashout() throws {
        let flat = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        var grade = VideoGrade()
        grade.chromaticAberration = 0.5
        let px = renderPixel(try GradeFilter(grade: grade).apply(flat))
        #expect(abs(px.r - 0.5) < 0.02 && abs(px.g - 0.5) < 0.02 && abs(px.b - 0.5) < 0.02)
    }
}

@Suite("Cut effects")
struct CutRenderTests {

    /// Only the compositing transitions run through Core Image here; plain
    /// dip/punch are handled consumer-side (a simple overlay / scale).
    @Test("CoreImage transitions are flagged; dip/punch are not")
    func needsCoreImage() {
        #expect(!CutRender.needsCoreImage(.none))
        #expect(!CutRender.needsCoreImage(.dipToBlack))
        #expect(!CutRender.needsCoreImage(.punchIn))
        #expect(CutRender.needsCoreImage(.whipPan))
        #expect(CutRender.needsCoreImage(.zoomBlur))
        #expect(CutRender.needsCoreImage(.glitch))
    }

    @Test("The glitch transition fringes a non-flat frame")
    func glitchAlters() {
        let gradient = CIFilter(name: "CILinearGradient")
        gradient?.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        gradient?.setValue(CIVector(x: 24, y: 0), forKey: "inputPoint1")
        gradient?.setValue(CIColor(red: 0, green: 0.2, blue: 0.6), forKey: "inputColor0")
        gradient?.setValue(CIColor(red: 1, green: 0.8, blue: 0.3), forKey: "inputColor1")
        let base = (gradient?.outputImage ?? CIImage(color: .gray))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 24))
        #expect(imageBytes(CutRender.apply(style: .glitch, strength: 1, to: base), side: 24)
                != imageBytes(base, side: 24))
        // Strength ~0 is a pass-through.
        #expect(imageBytes(CutRender.apply(style: .glitch, strength: 0, to: base), side: 24)
                == imageBytes(base, side: 24))
    }
}

@Suite("GradeColor")
struct GradeColorTests {

    @Test("Hex parsing maps to sRGB components")
    func hex() {
        let c = try! #require(GradeColor(hex: "#FFD60A"))
        #expect(abs(c.red - 1) < 0.005 && abs(c.green - 0.839) < 0.005 && abs(c.blue - 0.039) < 0.005)
        #expect(GradeColor(hex: "0A84FFFF")?.alpha == 1)
        #expect(GradeColor(hex: "nope") == nil)
    }

    @Test("Codable shape is red/green/blue/alpha (StyleColor-compatible)")
    func codableShape() throws {
        let data = try JSONEncoder().encode(GradeColor.blue)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Double]
        #expect(object?.keys.sorted() == ["alpha", "blue", "green", "red"])
    }
}

@Suite("PNG LUTs")
struct PNGLUTTests {

    @Test("Parses the tiled square layout correctly")
    func tiledLayout() throws {
        let dimension = 4, grid = 2, side = 8
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for blue in 0..<dimension {
            let tileX = (blue % grid) * dimension
            let tileY = (blue / grid) * dimension
            for green in 0..<dimension {
                for red in 0..<dimension {
                    let index = ((tileY + green) * side + tileX + red) * 4
                    pixels[index] = UInt8(red * 255 / (dimension - 1))
                    pixels[index + 1] = UInt8(green * 255 / (dimension - 1))
                    pixels[index + 2] = UInt8(blue * 255 / (dimension - 1))
                }
            }
        }
        let context = try #require(CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let parsed = try PNGLUTParser.parse(image: try #require(context.makeImage()))
        #expect(parsed.dimension == dimension)
        parsed.data.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            for (r, g, b) in [(0, 0, 0), (3, 0, 0), (0, 3, 0), (0, 0, 3), (2, 1, 3)] {
                let index = (r + dimension * g + dimension * dimension * b) * 4
                #expect(abs(Double(floats[index]) - Double(r) / 3) < 0.01)
                #expect(abs(Double(floats[index + 1]) - Double(g) / 3) < 0.01)
                #expect(abs(Double(floats[index + 2]) - Double(b) / 3) < 0.01)
            }
        }
    }

    @Test("Non-LUT image sizes are rejected")
    func rejectsBadSizes() {
        let context = CGContext(
            data: nil, width: 100, height: 60, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        #expect(throws: PNGLUTParser.PNGLUTError.self) {
            try PNGLUTParser.parse(image: context.makeImage()!)
        }
    }
}

@Suite("Lightroom presets")
struct LightroomPresetTests {

    @Test("Maps XMP develop sliders onto the grade")
    func mapping() {
        let xmp = """
        <x:xmpmeta><rdf:RDF><rdf:Description
         crs:Temperature="4900" crs:Tint="+3" crs:Exposure2012="+0.50"
         crs:Contrast2012="+20" crs:Highlights2012="-33" crs:Shadows2012="+26"
         crs:Vibrance="+10" crs:Saturation="-15" crs:Sharpness="40"
         crs:PostCropVignetteAmount="-30"
        /></rdf:RDF></x:xmpmeta>
        """
        let grade = LightroomPreset.grade(fromXMP: xmp)
        #expect(abs(grade.exposure - 0.5) < 0.001)
        #expect(abs(grade.contrast - 1.1) < 0.001)
        #expect(abs(grade.saturation - 0.85) < 0.001)
        #expect(abs(grade.vibrance - 0.1) < 0.001)
        #expect(abs(grade.temperature - 4900) < 0.001)
        #expect(abs(grade.tint - 3) < 0.001)
        #expect(grade.highlights < 1 && grade.highlights > 0.7)
        #expect(grade.shadows > 0.1)
        #expect(grade.vignette > 0.4)
        #expect(!grade.isNeutral)
    }

    @Test("Grayscale presets kill saturation")
    func grayscale() {
        let grade = LightroomPreset.grade(fromXMP: #"<rdf:Description crs:ConvertToGrayscale="True"/>"#)
        #expect(grade.saturation == 0)
    }
}
