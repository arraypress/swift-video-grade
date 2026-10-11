//
//  LightroomImport.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a Lightroom `.xmp` preset became: the grade, and the settings in
/// it that could not be applied — so a caller can say "approximated"
/// instead of pretending the look came across whole.
public struct LightroomImport: Equatable, Sendable {

    /// The grade the preset maps to.
    public var grade: VideoGrade

    /// Settings the preset changes that this engine does not reproduce,
    /// as `Key=value` (or a block name such as `masks`), sorted.
    public var unsupported: [String]

    public init(grade: VideoGrade, unsupported: [String]) {
        self.grade = grade
        self.unsupported = unsupported
    }
}
