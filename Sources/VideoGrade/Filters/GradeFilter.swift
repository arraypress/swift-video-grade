//
//  GradeFilter.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import CoreImage
import Foundation

/// Resolves a ``VideoGrade`` into a CoreImage pipeline.
///
/// **One builder, two consumers**: the exporter applies it per frame, and
/// the app applies the same instance through the player's video composition
/// — grading obeys the same parity rule as captions.
public struct GradeFilter: Sendable {

    /// The grade this filter was built from, exactly as given.
    public let grade: VideoGrade
    /// Parsed LUT, ready for `CIColorCube`.
    private let lut: (dimension: Int, data: Data)?
    /// Baked split-tone / skin-tone / B&W cube, built once from the grade.
    private let toneCube: (dimension: Int, data: Data)?
    /// Baked Lightroom develop cube (whites/blacks, mixer, B&W mix,
    /// grading, tone curve) over squeezed values, so HDR survives it.
    private let developCube: Data?

    /// Parsed LUTs, cached process-wide by path + modification time — a LUT
    /// is parsed once ever, shared across preview, thumbnails, and export.
    private final class LUTBox: NSObject {
        let dimension: Int
        let data: Data
        init(dimension: Int, data: Data) {
            self.dimension = dimension
            self.data = data
        }
    }

    // NSCache is documented thread-safe.
    nonisolated(unsafe) private static let lutCache = NSCache<NSString, LUTBox>()

    /// Loads (and parses the LUT of) a grade once; throws if the LUT file
    /// is unreadable. `.cube` text LUTs and tiled PNG/JPEG LUTs both work.
    public init(grade: VideoGrade) throws {
        self.grade = grade
        // Bake the hue/tone LUT up-front (once per grade change), not per frame.
        toneCube = ColorGradeCube.data(for: grade).map { (ColorGradeCube.dimension, $0) }
        developCube = DevelopCube.data(for: grade)
        guard let url = grade.lutURL, grade.lutIntensity > 0 else {
            lut = nil
            return
        }

        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            .map { "\($0.timeIntervalSince1970)" } ?? "0"
        let key = "\(url.path)|\(modified)" as NSString
        if let cached = Self.lutCache.object(forKey: key) {
            lut = (cached.dimension, cached.data)
            return
        }

        let parsed: (dimension: Int, data: Data)
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "tiff":
            parsed = try PNGLUTParser.parse(contentsOf: url)
        default:
            parsed = try CubeParser.parse(contentsOf: url)
        }
        Self.lutCache.setObject(LUTBox(dimension: parsed.dimension, data: parsed.data), forKey: key)
        lut = parsed
    }

    /// Applies the grade. Pure with respect to the input image; CIFilter
    /// objects are created per call, so the struct is safely Sendable.
    /// `time` (source seconds) only drives film-grain animation — everything
    /// else is time-invariant, so parity between preview and export holds.
    public func apply(_ input: CIImage, time: TimeInterval = 0) -> CIImage {
        var image = input

        if grade.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": grade.exposure])
        }
        if grade.levelsBlack != 0 || grade.levelsWhite != 1 || grade.levelsGamma != 1 {
            let black = grade.levelsBlack, white = max(grade.levelsWhite, black + 0.01)
            let gamma = max(0.05, grade.levelsGamma)
            let params: [String: Any] = Dictionary(uniqueKeysWithValues: (0...4).map { i in
                let x = Double(i) / 4
                let remapped = min(1, max(0, (x - black) / (white - black)))
                return ("inputPoint\(i)", CIVector(x: x, y: pow(remapped, gamma)))
            })
            image = image.applyingFilter("CIToneCurve", parameters: params)
        }
        if grade.temperature != 6500 || grade.tint != 0 {
            // `temperature` is stored in the intuitive convention (higher =
            // warmer, matching the slider and Lightroom). CITemperatureAndTint's
            // targetNeutral is the opposite — a LOWER target Kelvin warms the
            // image — so reflect the value around 6500 before handing it over.
            //
            // Clamped first, symmetrically: the reflection means the value
            // and 13000 minus it both reach the filter, and Kelvin below
            // about 2000 is off the Planckian locus — not a warmer white but
            // a degenerate one (13000K in came back with blue above red).
            // 2000–11000 keeps both ends on the locus, and spans candlelight
            // to arctic shade, which is every white balance a slider has
            // business setting.
            let temperature = min(max(grade.temperature, 2_000), 11_000)
            let target = 13_000 - temperature
            // Tint is inverted the same way: CITemperatureAndTint's target.y
            // positive shifts the image GREEN, but the slider (and Lightroom)
            // treat positive tint as MAGENTA — so negate it.
            let tint = min(max(grade.tint, -150), 150)
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: target, y: -tint),
            ])
        }
        // Lightroom Dehaze works on the scene before its tones are shaped.
        if grade.hazeRemoval != 0 {
            image = HazeRemoval.apply(image, amount: grade.hazeRemoval)
        }
        if grade.highlights != 1 || grade.shadows != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": grade.highlights,
                "inputShadowAmount": grade.shadows,
            ])
        }
        if grade.brightness != 0 || grade.contrast != 1 || grade.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                "inputBrightness": grade.brightness,
                "inputContrast": grade.contrast,
                "inputSaturation": grade.saturation,
            ])
        }
        if grade.vibrance != 0 {
            image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": grade.vibrance])
        }
        // Brilliance and Dehaze are per-pixel — baked exactly into the tone
        // cube (see ColorGradeCube), so nothing to do here.
        if grade.fade > 0 {
            // Matte fade: lift blacks toward a washed film look. Blend, by
            // amount, from identity toward the target 5-point curve.
            let amount = min(1, grade.fade)
            let target: [Double] = [0.3, 0.3, 0.5, 0.72, 1.0]
            let params: [String: Any] = Dictionary(uniqueKeysWithValues: (0...4).map { i in
                let x = Double(i) / 4
                return ("inputPoint\(i)", CIVector(x: x, y: target[i] * amount + x * (1 - amount)))
            })
            image = image.applyingFilter("CIToneCurve", parameters: params)
        }
        if grade.smoothing > 0 {
            image = image.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": grade.smoothing * 0.08,
                "inputSharpness": 0.4,
            ])
        }
        if grade.sharpness > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": grade.sharpness])
        }
        if let lut {
            let graded = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
                "inputCubeDimension": lut.dimension,
                "inputCubeData": lut.data,
                "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!,
            ])
            if grade.lutIntensity >= 1 {
                image = graded
            } else {
                image = graded.applyingFilter("CIDissolveTransition", parameters: [
                    "inputTargetImage": image,
                    "inputTime": 1 - grade.lutIntensity,
                ])
            }
        }
        // Split tone + skin tone + B&W, baked into one cube.
        if let toneCube {
            image = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
                "inputCubeDimension": toneCube.dimension,
                "inputCubeData": toneCube.data,
                "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!,
            ]).cropped(to: input.extent)
        }
        // Lightroom develop controls — tone, colour, then the tone curve —
        // as one cube that carries values above white.
        if let developCube {
            image = RangeShaper.apply(cube: developCube, dimension: DevelopCube.dimension, to: image)
        }
        // Filmic highlight rolloff: a soft shoulder near white so highlights
        // don't clip hard — blacks and midtones essentially untouched. Applied
        // before the bloom stages so they act on the rolled-off highlights.
        if grade.filmicRolloff > 0 {
            let a = min(1, grade.filmicRolloff)
            let x: [Double] = [0, 0.25, 0.5, 0.75, 1]
            let rolled: [Double] = [0, 0.25, 0.5, 0.72, 0.88]
            let params: [String: Any] = Dictionary(uniqueKeysWithValues: (0...4).map { i in
                ("inputPoint\(i)", CIVector(x: x[i], y: rolled[i] * a + x[i] * (1 - a)))
            })
            image = image.applyingFilter("CIToneCurve", parameters: params)
        }
        // Clarity: local-contrast punch — a wide-radius unsharp mask, unlike
        // the small-radius edge sharpen above.
        // Texture: the fine-detail band, below clarity's radius.
        if grade.texture != 0 {
            image = DetailBands.texture(image, amount: grade.texture)
        }
        if grade.clarity > 0 {
            image = image.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": 15.0,
                "inputIntensity": grade.clarity * 0.9,
            ]).cropped(to: input.extent)
        } else if grade.clarity < 0 {
            image = DetailBands.softenClarity(image, amount: grade.clarity)
        }
        // Glow/bloom: blur → soft bright-pass → screen back over the source.
        if grade.glow > 0 {
            let blurred = image
                .clampedToExtent() // else the blur pulls transparent edges in and fringes the frame
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": max(0, grade.glowRadius)])
                .cropped(to: image.extent)
            let highlights = blurred
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1.25, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1.25, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1.25, w: 0),
                    "inputBiasVector": CIVector(x: -0.25, y: -0.25, z: -0.25, w: 0),
                ])
                .applyingFilter("CIColorClamp")
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: grade.glow, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: grade.glow, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: grade.glow, w: 0),
                ])
            image = highlights
                .applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": image])
                .cropped(to: input.extent)
        }
        // Cinematic halation: isolate the brightest highlights, blur them into
        // a soft bloom, tint it warm red/orange (the film-base light-scatter
        // signature), and screen it back — a warm glow that hugs bright edges,
        // not a flat white bloom.
        if grade.halation > 0 {
            let threshold = 0.6
            let scale = 1 / (1 - threshold)
            let highlights = image
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
                    "inputBiasVector": CIVector(x: -threshold * scale, y: -threshold * scale, z: -threshold * scale, w: 0),
                ])
                .applyingFilter("CIColorClamp")
            let bloom = highlights
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": max(2, grade.halationRadius)])
                .cropped(to: image.extent)
            let amount = grade.halation
            // Warm tint: red carries most of the scatter, blue almost none.
            let warm = bloom.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.0 * amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.45 * amount, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.2 * amount, w: 0),
            ])
            image = warm
                .applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": image])
                .cropped(to: input.extent)
        }
        // Anamorphic flare: streak the brightest highlights horizontally and
        // tint them blue — the signature widescreen-lens light streak.
        if grade.anamorphicFlare > 0 {
            let amount = grade.anamorphicFlare
            let threshold = 0.65
            let scale = 1 / (1 - threshold)
            let bright = image
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
                    "inputBiasVector": CIVector(x: -threshold * scale, y: -threshold * scale, z: -threshold * scale, w: 0),
                ])
                .applyingFilter("CIColorClamp")
            let streak = bright
                .clampedToExtent()
                .applyingFilter("CIMotionBlur", parameters: ["inputRadius": 70, "inputAngle": 0])
                .cropped(to: image.extent)
            let blue = streak.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.25 * amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.55 * amount, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.1 * amount, w: 0),
            ])
            image = blue
                .applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": image])
                .cropped(to: input.extent)
        }
        // Light leak: a warm gradient bleeding from a frame edge, drifting and
        // pulsing over time, screened on.
        if grade.lightLeak > 0 {
            let amount = grade.lightLeak
            let extent = image.extent
            let drift = sin(time * 0.4) * 0.08
            let (cx, cy, tint): (Double, Double, (Double, Double, Double))
            switch grade.lightLeakStyle {
            case 1: (cx, cy, tint) = (0.0, 0.5, (1.0, 0.25, 0.15))   // left, red
            case 2: (cx, cy, tint) = (0.5, 0.0, (1.0, 0.75, 0.2))    // bottom, gold
            case 3: (cx, cy, tint) = (0.0, 1.0, (1.0, 0.3, 0.6))     // top-left, magenta
            default: (cx, cy, tint) = (1.0, 1.0, (1.0, 0.55, 0.15))  // top-right, amber
            }
            let center = CIVector(x: (cx + drift) * extent.width, y: cy * extent.height)
            let radius = max(extent.width, extent.height) * (0.55 + 0.2 * sin(time * 0.25))
            if let gradient = CIFilter(name: "CIRadialGradient") {
                gradient.setValue(center, forKey: "inputCenter")
                gradient.setValue(0.0, forKey: "inputRadius0")
                gradient.setValue(max(1, radius), forKey: "inputRadius1")
                gradient.setValue(CIColor(red: tint.0, green: tint.1, blue: tint.2, alpha: 1), forKey: "inputColor0")
                gradient.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 1), forKey: "inputColor1")
                if let leak = gradient.outputImage?.cropped(to: extent) {
                    let scaled = leak.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
                    ])
                    image = scaled
                        .applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": image])
                        .cropped(to: input.extent)
                }
            }
        }
        // Lens chromatic aberration: scale the red channel slightly out and the
        // blue slightly in about the center, then recombine — so R/B fringing
        // is zero at the center and grows toward the edges, like a real lens.
        if grade.chromaticAberration > 0 {
            let extent = image.extent
            let center = CGPoint(x: extent.midX, y: extent.midY)
            let k = grade.chromaticAberration * 0.012
            func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, scale: CGFloat) -> CIImage {
                // Isolate one channel (zero in the other two); alpha stays 1 so
                // the per-channel MAX recombine below reads its value.
                let isolated = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                ])
                guard scale != 1 else { return isolated }
                let transform = CGAffineTransform(translationX: center.x, y: center.y)
                    .scaledBy(x: scale, y: scale)
                    .translatedBy(x: -center.x, y: -center.y)
                return isolated.clampedToExtent().transformed(by: transform).cropped(to: extent)
            }
            let red = channel(1, 0, 0, scale: 1 + k)
            let green = channel(0, 1, 0, scale: 1)
            let blue = channel(0, 0, 1, scale: 1 - k)
            // The three channels are disjoint (each zero in the other two), so a
            // per-channel MAX recombines them exactly — and, unlike additive
            // compositing, it leaves alpha at 1 instead of summing it to 3 (that
            // over-alpha washed out every stage downstream).
            image = red
                .applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": green])
                .applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": blue])
                .cropped(to: input.extent)
        }
        // Film grain: gray noise soft-lit over the frame. Shifted per frame by
        // `time` so it actually twinkles instead of sitting static.
        if grade.grain > 0 {
            let dx = (time * 613).truncatingRemainder(dividingBy: 512)
            let dy = (time * 971).truncatingRemainder(dividingBy: 512)
            let noise = (CIFilter(name: "CIRandomGenerator")?.outputImage ?? image)
                .transformed(by: CGAffineTransform(translationX: dx, y: dy))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: grade.grain * 0.6),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                ])
                .cropped(to: image.extent)
            image = noise
                .applyingFilter("CISoftLightBlendMode", parameters: ["inputBackgroundImage": image])
                .cropped(to: input.extent)
        }
        // Old-film damage: sparse vertical scratches (one row of thresholded
        // noise stretched to full height) plus dust specks, both drifting per
        // frame and screened on faintly.
        if grade.filmDamage > 0 {
            let amount = grade.filmDamage
            let extent = image.extent
            let sx = (time * 137).truncatingRemainder(dividingBy: 512)
            let scratchRow = (CIFilter(name: "CIRandomGenerator")?.outputImage ?? image)
                .transformed(by: CGAffineTransform(translationX: sx, y: 0))
                .applyingFilter("CIColorControls", parameters: ["inputContrast": 14, "inputBrightness": -6, "inputSaturation": 0])
                .applyingFilter("CIColorClamp")
                .cropped(to: CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: 1))
            let scratches = scratchRow
                .transformed(by: CGAffineTransform(scaleX: 1, y: extent.height))
                .cropped(to: extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: amount * 0.6, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: amount * 0.6, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: amount * 0.6, w: 0),
                ])
            let dust = (CIFilter(name: "CIRandomGenerator")?.outputImage ?? image)
                .transformed(by: CGAffineTransform(translationX: (time * 91).truncatingRemainder(dividingBy: 512), y: sx))
                .applyingFilter("CIColorControls", parameters: ["inputContrast": 24, "inputBrightness": -11, "inputSaturation": 0])
                .applyingFilter("CIColorClamp")
                .cropped(to: extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: amount * 0.7, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: amount * 0.7, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: amount * 0.7, w: 0),
                ])
            var damaged = scratches.applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": image]).cropped(to: extent)
            damaged = dust.applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": damaged]).cropped(to: extent)
            image = damaged.cropped(to: input.extent)
        }
        if grade.vignette > 0 {
            image = image.applyingFilter("CIVignette", parameters: [
                "inputIntensity": grade.vignette,
                "inputRadius": 1.6,
            ])
        }
        return image.cropped(to: input.extent)
    }
}

