// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VideoGrade",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        // A color-grading + film-look engine for video frames. Pure Core Image
        // (no Metal/metallib) so one filter builder drives both a live
        // AVPlayerItem.videoComposition and an offline exporter identically.
        .library(name: "VideoGrade", targets: ["VideoGrade"]),

        // Interactive SwiftUI controls that bind to a `Binding<VideoGrade>` —
        // a curves graph, split-tone wheels, a B&W hue bar, a 12-band HSL
        // editor, and a levels ramp. Separate product so the engine stays
        // headless for non-UI consumers.
        .library(name: "VideoGradeUI", targets: ["VideoGradeUI"]),
    ],
    targets: [
        .target(name: "VideoGrade"),
        .target(name: "VideoGradeUI", dependencies: ["VideoGrade"]),
        .testTarget(name: "VideoGradeTests", dependencies: ["VideoGrade"]),
    ]
)
