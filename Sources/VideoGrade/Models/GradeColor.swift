//
//  GradeColor.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// A platform-neutral, serializable sRGB color — used by ``VideoGrade`` for its
/// split-tone tints.
///
/// The grade engine is headless and cross-platform, so it can't use
/// `NSColor`/`UIColor`, and `CGColor` isn't `Codable`; grades store colors as
/// plain sRGB components and resolve to `CGColor` at render time. Its `Codable`
/// shape (`red` / `green` / `blue` / `alpha`) is intentionally **identical** to
/// CaptionKit's `StyleColor`, so grades embedded in older project files decode
/// unchanged after the split into this package.
public struct GradeColor: Codable, Equatable, Hashable, Sendable {

    /// Red component (`0…1`, sRGB).
    public var red: Double

    /// Green component (`0…1`, sRGB).
    public var green: Double

    /// Blue component (`0…1`, sRGB).
    public var blue: Double

    /// Alpha component (`0…1`).
    public var alpha: Double

    /// Creates a color from sRGB components (`0…1`).
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Creates a color from a hex string like `"#FFD60A"`, `"FFD60A"`, or
    /// `"#FFD60AFF"` (with alpha). Returns `nil` for malformed input.
    public init?(hex: String) {
        guard let c = GradeColorHex.components(hex) else { return nil }
        self.init(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    /// The same color with a different alpha.
    public func withAlpha(_ alpha: Double) -> GradeColor {
        GradeColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Resolves to a `CGColor` in the sRGB color space.
    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    // MARK: - Presets

    public static let white = GradeColor(red: 1, green: 1, blue: 1)
    public static let black = GradeColor(red: 0, green: 0, blue: 0)
    public static let clear = GradeColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let yellow = GradeColor(red: 1, green: 0.84, blue: 0.04)
    public static let green = GradeColor(red: 0.20, green: 0.84, blue: 0.29)
    public static let red = GradeColor(red: 1, green: 0.23, blue: 0.19)
    public static let blue = GradeColor(red: 0.04, green: 0.52, blue: 1)
    public static let purple = GradeColor(red: 0.75, green: 0.35, blue: 0.95)
    public static let orange = GradeColor(red: 1, green: 0.58, blue: 0)
    public static let pink = GradeColor(red: 1, green: 0.18, blue: 0.57)
}
