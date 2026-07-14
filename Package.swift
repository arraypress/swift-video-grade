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
    ],
    targets: [
        .target(name: "VideoGrade"),
        .testTarget(name: "VideoGradeTests", dependencies: ["VideoGrade"]),
    ]
)
