//
//  VideoGrade+Sliders.swift
//  VideoGrade
//
//  Created by David Sherlock on 2026.
//

public extension VideoGrade {

    /// White balance as a slider: `-1` cooler … `1` warmer, `0` untouched
    /// (4000…9000 K around 6500). Bind a UI slider or a CLI flag to this,
    /// not to ``temperature``, which is Kelvin.
    var temperatureSlider: Double {
        get { SliderScale.slider(kelvin: temperature) }
        set { temperature = SliderScale.kelvin(newValue) }
    }

    /// Tint as a slider: `-1` green … `1` magenta, `0` untouched.
    var tintSlider: Double {
        get { SliderScale.slider(tint: tint) }
        set { tint = SliderScale.tint(newValue) }
    }

    /// Highlight recovery as a slider: `0` none … `1` strongest.
    var highlightRecovery: Double {
        get { SliderScale.recovery(highlights: highlights) }
        set { highlights = SliderScale.highlights(recovery: newValue) }
    }
}
