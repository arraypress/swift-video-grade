# VideoGrade

A color-grading and film-look engine for video frames — **pure Core Image, zero
dependencies**. One filter builder drives both a live
`AVPlayerItem.videoComposition` and an offline exporter, so preview and export
match by construction.

```swift
import VideoGrade

var grade = VideoGrade()
grade.contrast = 1.1
grade.splitShadow = .blue
grade.splitShadowAmount = 0.4
grade.grain = 0.2

let filter = try GradeFilter(grade: grade)
let output = filter.apply(inputImage, time: currentTime)   // CIImage → CIImage
```

## What it does

`VideoGrade` is a pure-data description; `GradeFilter` resolves it to Core Image.

- **Tone / color:** exposure, brightness, contrast, saturation, vibrance,
  temperature, tint, highlights, shadows, levels (black/white/gamma), tone
  curves (master + per-channel), clarity, brilliance, dehaze.
- **Color grading:** split-tone (shadow/highlight tints), a per-hue B&W mixer,
  full 12-band HSL, skin-tone protection.
- **Film look:** fade, grain, glow/bloom, halation, filmic highlight rolloff,
  light leaks, anamorphic flare, film damage, chromatic aberration, vignette.
- **Lightroom develop controls (0.2):** whites, blacks, texture, dehaze
  (dark-channel prior), the parametric + point tone curve, the eight-band
  colour mixer, black & white mix and three-way colour grading — see below.
- **LUTs:** `.cube` files and PNG "HALD"/square LUTs; Adobe Lightroom `.xmp`
  develop presets mapped onto the grade, with what could not be mapped listed.
- **Skin smoothing** (`SkinSmoothFilter`) and **cut-transition effects**
  (`CutRender` — dip to black/white, punch-in, whip-pan, zoom-blur, glitch).

The heavy per-pixel work (B&W mixer, 12-band HSL, split-tone, skin tone, curves,
brilliance, dehaze) is baked once into a single 32³ `CIColorCube`
(`ColorGradeCube`); spatial effects (blur, unsharp, bloom, gradients) are Core
Image filter stages. Animated effects (grain, light leaks, film damage) read a
`time:` parameter so they move frame to frame.

## Lightroom develop controls

```swift
var grade = VideoGrade()
grade.whites = 0.2; grade.blacks = -0.3; grade.texture = 0.3; grade.hazeRemoval = 0.4
grade.toneCurve = ToneCurve(darks: 0.2, master: [CGPoint(x: 0, y: 0.04), CGPoint(x: 1, y: 0.96)])
var mixer = ColorMixer(); mixer.blue = MixerBand(saturation: -0.4); grade.colorMixer = mixer
grade.colorGrading = ColorGrading(shadows: GradingWheel(hue: 210, saturation: 0.25))
grade.monochromeMix = MonochromeMix(red: 0.2)          // set = black & white

let imported = try LightroomPreset.importPreset(contentsOf: presetURL)
imported.grade          // the look
imported.unsupported    // e.g. ["CameraProfile=Camera Vivid", "masks", "profile look (Look)"]
```

Sliders are Lightroom's −100…100 as −1…1. The definitions — formulas and
constants — come from **[LightCraft](https://github.com/storytold/lightcraft)**,
a clean-room Lightroom reimplementation (MIT OR Apache-2.0; see `NOTICE`):
mixer, B&W and grading in OkLab/OkLCh with bands centred on the sRGB hues
0/30/60/120/180/225/270/315°, whites/blacks in a gamma-2.2 domain, the
parametric curve's raised-cosine regions, monotone (Fritsch–Carlson) point
curves, and Dehaze's t = max(1 − 0.95·amount·dark/A, 0.12). **Built to
Lightroom's definitions, not yet measured against Lightroom itself.**

How it runs, all built-in Core Image (iOS and macOS):

- **Per-pixel controls** bake into one 64³ cube over a *squeezed* range: a 1D
  curve maps 0…1 linearly to 0…0.8 and rolls values above white (up to 63
  encoded) into the rest, the cube runs, and the inverse curve stretches back.
  A plain colour cube clamps at 1; this carries HDR through. Baking takes
  0.10 s per grade (release, M-series), once, not per frame.
- **Dehaze** is a graph: the divide blend clamps to 0…1, so J is written as
  I·R(x) + A·S(x) with R and S as 1D curves of x = dark/A, in linear light
  whatever the host's working space.
- **Texture** is the unsharp-mask equivalent at LightCraft's radius (0.18 % of
  the long edge); a negative unsharp mask is a no-op in Core Image, so
  smoothing — and negative clarity — blend toward the blur.
- **Point curves can't invert a tone**: outputs are made non-decreasing before
  the spline, whatever order the points come in.

Measured by the test suite on generated linear scenes (no external images):

| Check | Result |
|---|---|
| Grades written by 0.1.1, rendered now vs then | max \|Δ\| = 0.0 (three goldens) |
| Every new control at its default | max \|Δ\| = 0.0, HDR and alpha included |
| Curve with points out of order and doubling back | largest step down 0.0 rendered |
| Mixer blue band at full hue/sat/lum | other hues (outside 180–270°) move ≤ 0.0026; blue moves 0.56 |
| Shadows wheel at full saturation | tint above OkLab L 0.65 ≤ 0.0005 (0.23 in range) |
| Highlights wheel at full saturation | tint below L 0.35 ≤ 0.0002 (0.41 in range) |
| B&W mix | channel spread 0.0; blue +100 lifts blue 0.28, red 0.0 |
| Dehaze on haze of known t and A (I = J·t + A·(1−t)) | mean \|J − ·\| 0.209 → 0.0146; same in an sRGB working space |
| HDR 4.0 through curve / everything / dehaze / texture | 4.17 / 4.17 / 4.00 / 4.00 |
| Transparent pixels, everything on | stay exactly 0; alpha drift 6e−8 |

The 64³ cube costs about 0.003 of interpolation error in SDR (measured on an
identity cube) — below 8-bit precision, but not zero, which is why every
control stays off the cube path until it is set.

`LightroomPreset.importPreset` maps the basic panel, whites/blacks, clarity,
texture, dehaze, the tone curve (`ToneCurvePV2012` + Red/Green/Blue and
`Parametric*`), `HueAdjustment*`/`SaturationAdjustment*`/`LuminanceAdjustment*`,
`ColorGrade*` and `SplitToning*`, `GrayMixer*` with `ConvertToGrayscale`, dark
vignette and grain amount. It reports — never silently drops — the rest:
camera profiles and looks, masks, lens corrections, noise reduction, grain
size/roughness, white vignettes, process-2010 curves. Metadata and Lightroom's
own defaults are not reported. Settings nested inside a mask or look stay
there.

## Notes

- **Parity is the consumer's job:** build the filter once and use the *same*
  instance for preview and export. A footage effect that looks different in the
  two is a bug in the host's stage ordering, not here.
- Colors are `GradeColor` (plain sRGB components), serialized as
  `{red, green, blue, alpha}` — the same shape as CaptionKit's `StyleColor`, so
  grades embedded in existing documents keep decoding after this split.
- Several algorithms are re-authored from the author-owned *FilterSpark* shaders
  as Core Image (no Metal/metallib). `brilliance`/`dehaze` are pixel-exact
  ports; the 12-band HSL uses standard *wrapped* hue.

## The UI product

`VideoGradeUI` is a separate library product — SwiftUI controls that bind to a
`Binding<VideoGrade>`: a curves graph, split-tone wheels, a B&W hue bar, a
12-band HSL editor, and a levels ramp. Separate so the engine stays headless
for non-UI consumers.

## Requirements

macOS 26 / iOS 26, Swift 6.2. No external dependencies. Both products build for
the iOS Simulator (checked with `xcodebuild -destination 'generic/platform=iOS Simulator'`).

## Tests

```
swift test
```

## License

MIT — see [LICENSE](LICENSE). Ported LightCraft material is credited in [NOTICE](NOTICE).

---

This project is independent and is not affiliated with, endorsed by, or sponsored by Adobe Inc. Adobe and Lightroom are trademarks of Adobe Inc., registered in the U.S. and other countries.
