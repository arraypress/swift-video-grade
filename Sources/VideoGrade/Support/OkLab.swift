//
//  OkLab.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//
//  OkLab / OkLCh (Björn Ottosson, 2020) on linear sRGB, and the sRGB
//  transfer curve extended to every real number (sign-preserving, linear
//  continuation) so values above 1 and below 0 survive a round trip.
//

import Foundation

/// Colour-space conversions for the develop tools.
enum OkLab {

    /// Linear sRGB → OkLab `(L, a, b)`.
    static func fromLinear(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    /// OkLab → linear sRGB.
    static func toLinear(_ L: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    /// OkLab → OkLCh `(L, C, h)`, `h` in radians.
    static func lch(_ L: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
        (L, (a * a + b * b).squareRoot(), atan2(b, a))
    }

    /// OkLCh → OkLab.
    static func lab(_ L: Double, _ c: Double, _ h: Double) -> (Double, Double, Double) {
        (L, c * cos(h), c * sin(h))
    }

    /// sRGB-encoded → linear, extended (odd-symmetric) beyond `0…1`.
    static func decode(_ v: Double) -> Double {
        let a = abs(v)
        let lin = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
        return v < 0 ? -lin : lin
    }

    /// Linear → sRGB-encoded, extended (odd-symmetric) beyond `0…1`.
    static func encode(_ v: Double) -> Double {
        let a = abs(v)
        let enc = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055
        return v < 0 ? -enc : enc
    }

    /// OkLCh hue (radians) of a fully saturated sRGB colour of HSV hue `degrees`.
    static func hue(ofSRGBHue degrees: Double) -> Double {
        let (r, g, b) = hsvToRGB(degrees / 360, 1, 1)
        let lab = fromLinear(decode(r), decode(g), decode(b))
        return atan2(lab.2, lab.1)
    }

    /// HSV (`h` in turns) → sRGB-encoded.
    static func hsvToRGB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let hh = (h - floor(h)) * 6
        let i = Int(hh) % 6
        let f = hh - floor(hh)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// An angle wrapped into `-π…π`.
    static func wrap(_ a: Double) -> Double {
        let twoPi = 2 * Double.pi
        var x = (a + .pi).truncatingRemainder(dividingBy: twoPi)
        if x < 0 { x += twoPi }
        return x - .pi
    }

    /// Hermite smoothstep.
    static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }
}
