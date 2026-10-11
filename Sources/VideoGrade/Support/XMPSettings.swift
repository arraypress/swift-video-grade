//
//  XMPSettings.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  The Camera Raw settings in an XMP packet, in either of the two forms
//  Lightroom writes — `crs:Key="value"` attributes and `<crs:Key>value
//  </crs:Key>` elements — plus `rdf:Seq` point lists (tone curves) and the
//  names of nested blocks (masks, looks) that hold no single value.
//

import CoreGraphics
import Foundation

/// The `crs:` settings of an XMP preset.
struct XMPSettings {

    /// Plain values by key, as written.
    let values: [String: String]

    /// `rdf:Seq` lists by key (tone curves), each item as written.
    let lists: [String: [String]]

    /// Keys of nested blocks that are neither a value nor a list.
    let blocks: Set<String>

    init(_ text: String) {
        var values: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var blocks = Set<String>()
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)

        // Elements first. Anything nested inside one (a look's own
        // crs:Amount, a mask's crs:LocalExposure2012) belongs to that
        // block, so block bodies are cut out before attributes are read.
        var nested: [NSRange] = []
        for m in Self.element.matches(in: text, range: all) {
            let key = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2))
            if !body.contains("<") {
                values[key] = body.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            nested.append(m.range(at: 2))
            if body.contains("<rdf:Seq") {
                let b = body as NSString
                lists[key] = Self.item.matches(in: body, range: NSRange(location: 0, length: b.length))
                    .map { b.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
            } else {
                blocks.insert(key)
            }
        }
        let flat = NSMutableString(string: text)
        for range in nested.sorted(by: { $0.location > $1.location }) {
            flat.replaceCharacters(in: range, with: "")
        }
        let top = flat as String
        let topRange = NSRange(location: 0, length: flat.length)
        for m in Self.attribute.matches(in: top, range: topRange) {
            values[flat.substring(with: m.range(at: 1))] = flat.substring(with: m.range(at: 2))
        }
        // A self-closing element (<crs:Look .../>) or one opened with
        // attributes is a block as well.
        for m in Self.opening.matches(in: top, range: topRange) {
            let key = flat.substring(with: m.range(at: 1))
            if values[key] == nil, lists[key] == nil { blocks.insert(key) }
        }
        self.values = values
        self.lists = lists
        self.blocks = blocks
    }

    /// A numeric value (`+1.50` reads as 1.5).
    func number(_ key: String) -> Double? {
        values[key].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// A boolean value.
    func flag(_ key: String) -> Bool {
        values[key].map { $0.caseInsensitiveCompare("True") == .orderedSame } ?? false
    }

    /// A point list `"x, y"` in `0…255`, as `0…1` points.
    func points(_ key: String) -> [CGPoint]? {
        guard let items = lists[key] else { return nil }
        let points = items.compactMap { item -> CGPoint? in
            let parts = item.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else { return nil }
            return CGPoint(x: parts[0] / 255, y: parts[1] / 255)
        }
        return points.count >= 2 ? points : nil
    }

    private static let attribute = try! NSRegularExpression(pattern: #"crs:([A-Za-z0-9]+)="([^"]*)""#)
    private static let element = try! NSRegularExpression(
        pattern: #"<crs:([A-Za-z0-9]+)>(.*?)</crs:\1>"#, options: [.dotMatchesLineSeparators])
    private static let item = try! NSRegularExpression(
        pattern: #"<rdf:li>(.*?)</rdf:li>"#, options: [.dotMatchesLineSeparators])
    private static let opening = try! NSRegularExpression(pattern: #"<crs:([A-Za-z0-9]+)[\s/>]"#)
}
