//
//  GradientSlider.swift
//  VideoGradeUI
//
//  Created by David Sherlock on 2026.
//

import SwiftUI

/// A labelled slider whose track is a color gradient — reads the value on the
/// right, double-click to reset. Used by the grade controls, and handy for any
/// tinted parameter.
public struct GradientSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let colors: [Color]
    var format: String
    var resetValue: CGFloat?

    public init(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        colors: [Color],
        format: String = "%.2f",
        resetValue: CGFloat? = nil
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.colors = colors
        self.format = format
        self.resetValue = resetValue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if let resetValue { value = resetValue }
            }
            .help(resetValue != nil ? "Double-click to reset" : "")

            GeometryReader { geometry in
                let width = geometry.size.width
                let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 10)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(radius: 1.5)
                        .offset(x: fraction * (width - 14))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let f = min(1, max(0, gesture.location.x / max(1, width)))
                            value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                        }
                )
            }
            .frame(height: 16)
        }
    }
}
