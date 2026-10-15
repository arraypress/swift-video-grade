//
//  LookFile.swift
//  VideoGradeLook
//
//  Created by David Sherlock on 2026.
//
//  A look read from a file someone points at: an img or vid recipe (its
//  `grade` section — `img grade --save-recipe look.json` writes one), or a
//  file holding a grade section alone. Read strictly: a misspelt setting is
//  refused with the setting it was likely meant to be, never ignored.
//

import Foundation
import RecipeKit
import VideoGrade

public enum LookFile {

    /// The look in the file at `url`, its LUT path made absolute.
    public static func read(_ url: URL) throws(RecipeError) -> GradeLook {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw RecipeError("no look at \(url.path)") }
        return try decoded(data, folder: url.deletingLastPathComponent())
    }

    /// The look in `data`; a relative LUT path is taken from `folder`.
    public static func decoded(_ data: Data, folder: URL) throws(RecipeError) -> GradeLook {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch { throw RecipeError("it is not JSON") }
        guard let root = object as? [String: Any] else { throw RecipeError("it is not a JSON object") }
        let section = (root["grade"] as? [String: Any]) ?? root
        let wrapped: Data
        do { wrapped = try JSONSerialization.data(withJSONObject: ["look": 1, "grade": section]) } catch {
            throw RecipeError("cannot read it: \(error.localizedDescription)")
        }
        var look = try RecipeJSON.decoded(wrapped, as: Wrapper.self, format: format) { root throws(RecipeError) in
            try GradeLookJSON.check(root["grade"], at: "grade")
        }.grade
        if let lut = look.lut { look.lut = RecipePaths.usable(lut, from: folder) }
        return look
    }

    /// The strict shape: one grade section.
    static let format = RecipeFormat(versionKey: "look", version: 1, rootKeys: ["look", "grade"],
                                     sections: GradeLookJSON.sections(under: "grade"), suggests: true)

    struct Wrapper: Codable {
        var grade: GradeLook
    }
}
