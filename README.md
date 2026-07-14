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
- **LUTs:** `.cube` files and PNG "HALD"/square LUTs; Adobe Lightroom `.xmp`
  develop presets mapped onto the grade.
- **Skin smoothing** (`SkinSmoothFilter`) and **cut-transition effects**
  (`CutRender` — dip to black/white, punch-in, whip-pan, zoom-blur, glitch).

The heavy per-pixel work (B&W mixer, 12-band HSL, split-tone, skin tone, curves,
brilliance, dehaze) is baked once into a single 32³ `CIColorCube`
(`ColorGradeCube`); spatial effects (blur, unsharp, bloom, gradients) are Core
Image filter stages. Animated effects (grain, light leaks, film damage) read a
`time:` parameter so they move frame to frame.

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

## Requirements

macOS 26 / iOS 26, Swift 6.2. No external dependencies.

## Tests

```
swift test
```
