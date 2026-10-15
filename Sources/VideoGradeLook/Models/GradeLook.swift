//
//  GradeLook.swift
//  VideoGradeLook
//
//  Created by David Sherlock on 2026.
//
//  The `grade` section of a recipe: a VideoGrade, written as the settings
//  that differ from untouched (so a look file is short enough to read and
//  edit), in snake_case, with the LUT as a path. img, vid and design write
//  and read the same shape, so one look file serves them all. The reading
//  and writing rules are in ``GradeLookJSON``.
//

import Foundation
import VideoGrade

/// A grade as a recipe holds it.
public struct GradeLook: Codable, Equatable, Sendable {

    /// The grade, without its LUT (that is ``lut``).
    public var grade: VideoGrade

    /// The LUT's path: absolute in memory, relative to the recipe on disk
    /// when the LUT sits beside it.
    public var lut: String?

    /// A look from a grade, its LUT taken out as a path.
    public init(_ grade: VideoGrade) {
        var bare = grade
        bare.lutURL = nil
        self.grade = bare
        lut = grade.lutURL?.path
    }

    /// The grade the engine runs: the LUT put back.
    public var resolved: VideoGrade {
        var grade = grade
        grade.lutURL = lut.map { URL(fileURLWithPath: $0) }
        return grade
    }

    public init(from decoder: any Decoder) throws {
        (grade, lut) = try GradeLookJSON.decode(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try GradeLookJSON.object(for: self).encode(to: encoder)
    }
}
