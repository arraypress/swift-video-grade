//
//  GradeControls.swift
//  VideoGradeUI
//
//  Created by David Sherlock on 2026.
//
//  Purpose-built, interactive grade controls — a curves graph you drag, color
//  wheels for split toning, a hue bar for the B&W mixer, a 12-band HSL editor,
//  and a levels ramp — so grading isn't a wall of sliders.
//
//  Each binds to a `Binding<VideoGrade>`; the host decides what a mutation
//  means (e.g. wrap the binding's setter to snapshot for undo). Controls that
//  can draw a histogram behind the graph take an optional `histogram: [Float]`
//  (0…1 bins) — pass an empty array to omit it.
//

import SwiftUI
import VideoGrade

// MARK: - RGB Curves

/// An interactive tone-curve editor: pick a channel, drag points on the graph,
/// tap empty space to add a point, drag a point off the bottom to remove it.
public struct CurvesEditor: View {
    @Binding var grade: VideoGrade
    var histogram: [Float]

    public init(grade: Binding<VideoGrade>, histogram: [Float] = []) {
        self._grade = grade
        self.histogram = histogram
    }

    enum Channel: String, CaseIterable, Identifiable {
        case rgb = "RGB", red = "R", green = "G", blue = "B"
        var id: String { rawValue }
        var tint: Color {
            switch self {
            case .rgb: return .primary
            case .red: return .red
            case .green: return .green
            case .blue: return .blue
            }
        }
        var keyPath: WritableKeyPath<VideoGrade, [CGPoint]?> {
            switch self {
            case .rgb: return \.curveRGB
            case .red: return \.curveRed
            case .green: return \.curveGreen
            case .blue: return \.curveBlue
            }
        }
    }

    @State private var channel: Channel = .rgb
    @State private var dragIndex: Int?
    private let identity = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]

    private var points: [CGPoint] {
        (grade[keyPath: channel.keyPath] ?? identity).sorted { $0.x < $1.x }
    }

    private func commit(_ pts: [CGPoint]) {
        let sorted = pts.sorted { $0.x < $1.x }
        let isIdentity = sorted.count == 2
            && abs(sorted[0].x) < 0.002 && abs(sorted[0].y) < 0.002
            && abs(sorted[1].x - 1) < 0.002 && abs(sorted[1].y - 1) < 0.002
        grade[keyPath: channel.keyPath] = isIdentity ? nil : sorted
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $channel) {
                    ForEach(Channel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button {
                    grade[keyPath: channel.keyPath] = nil
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset this channel to a straight line")
            }

            GeometryReader { geo in
                let size = min(geo.size.width, 220)
                graph(side: size)
                    .frame(width: size, height: size)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 220)

            Text("Drag to bend · tap to add a point · drag a point off the bottom to remove")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func graph(side: CGFloat) -> some View {
        let pts = points
        return ZStack {
            Canvas { context, canvasSize in
                let w = canvasSize.width, h = canvasSize.height
                if histogram.count > 1 {
                    var fill = Path()
                    fill.move(to: CGPoint(x: 0, y: h))
                    for (i, v) in histogram.enumerated() {
                        fill.addLine(to: CGPoint(x: CGFloat(i) / CGFloat(histogram.count - 1) * w, y: h - CGFloat(v) * h))
                    }
                    fill.addLine(to: CGPoint(x: w, y: h))
                    fill.closeSubpath()
                    context.fill(fill, with: .color(.white.opacity(0.14)))
                }
                var grid = Path()
                for i in 0...4 {
                    let f = CGFloat(i) / 4
                    grid.move(to: CGPoint(x: f * w, y: 0)); grid.addLine(to: CGPoint(x: f * w, y: h))
                    grid.move(to: CGPoint(x: 0, y: f * h)); grid.addLine(to: CGPoint(x: w, y: f * h))
                }
                context.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
                var diag = Path()
                diag.move(to: CGPoint(x: 0, y: h)); diag.addLine(to: CGPoint(x: w, y: 0))
                context.stroke(diag, with: .color(.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                var curve = Path()
                for (i, p) in pts.enumerated() {
                    let point = CGPoint(x: p.x * w, y: (1 - p.y) * h)
                    if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
                }
                context.stroke(curve, with: .color(channel.tint == .primary ? .white : channel.tint), lineWidth: 2)
                for p in pts {
                    let c = CGPoint(x: p.x * w, y: (1 - p.y) * h)
                    let dot = Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
                    context.fill(dot, with: .color(channel.tint == .primary ? .white : channel.tint))
                    context.stroke(dot, with: .color(.black.opacity(0.5)), lineWidth: 1)
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
            .contentShape(Rectangle())
            .gesture(dragGesture(side: side))
        }
    }

    private func dragGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var pts = points
                let x = Double(max(0, min(1, value.location.x / side)))
                let y = Double(max(0, min(1, 1 - value.location.y / side)))

                if dragIndex == nil {
                    let hitRadius = 0.06
                    if let near = pts.enumerated().min(by: { abs($0.element.x - x) < abs($1.element.x - x) }),
                       abs(near.element.x - x) < hitRadius {
                        dragIndex = near.offset
                    } else {
                        pts.append(CGPoint(x: x, y: y))
                        pts.sort { $0.x < $1.x }
                        dragIndex = pts.firstIndex { abs($0.x - x) < 0.001 }
                        commit(pts)
                        return
                    }
                }
                guard let index = dragIndex, pts.indices.contains(index) else { return }
                let isEndpoint = index == 0 || index == pts.count - 1
                var newX = pts[index].x
                if !isEndpoint {
                    let lo = pts[index - 1].x + 0.02
                    let hi = pts[index + 1].x - 0.02
                    newX = CGFloat(max(Double(lo), min(Double(hi), x)))
                }
                pts[index] = CGPoint(x: newX, y: CGFloat(y))
                commit(pts)
            }
            .onEnded { value in
                var pts = points
                if let index = dragIndex, pts.indices.contains(index),
                   index != 0, index != pts.count - 1,
                   value.location.y > side + 18 {
                    pts.remove(at: index)
                    commit(pts)
                }
                dragIndex = nil
            }
    }
}

// MARK: - Split-tone color wheel

/// A hue/amount wheel: angle picks the tint hue, distance from center sets the
/// strength. Used for both the shadow and highlight split-tone tints.
public struct SplitToneWheel: View {
    let title: String
    @Binding var grade: VideoGrade
    let colorKey: WritableKeyPath<VideoGrade, GradeColor?>
    let amountKey: WritableKeyPath<VideoGrade, Double>

    public init(
        title: String,
        grade: Binding<VideoGrade>,
        colorKey: WritableKeyPath<VideoGrade, GradeColor?>,
        amountKey: WritableKeyPath<VideoGrade, Double>
    ) {
        self.title = title
        self._grade = grade
        self.colorKey = colorKey
        self.amountKey = amountKey
    }

    private var amount: Double { grade[keyPath: amountKey] }
    private var hue: Double {
        guard let color = grade[keyPath: colorKey] else { return 0 }
        return Self.hue(r: color.red, g: color.green, b: color.blue)
    }

    public var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                wheel(side: side)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 110)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func wheel(side: CGFloat) -> some View {
        let radius = side / 2
        let puck = CGPoint(
            x: radius + cos(hue * 2 * .pi) * radius * amount,
            y: radius + sin(hue * 2 * .pi) * radius * amount
        )
        return ZStack {
            Circle()
                .fill(AngularGradient(
                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                    center: .center
                ))
                .overlay(Circle().fill(RadialGradient(
                    colors: [Color(white: 0.5), .clear],
                    center: .center, startRadius: 0, endRadius: radius
                )))
                .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 1))
            Circle()
                .stroke(.white, lineWidth: 2)
                .background(Circle().fill(.black.opacity(0.25)))
                .frame(width: 12, height: 12)
                .position(puck)
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let dx = value.location.x - radius
            let dy = value.location.y - radius
            let dist = min(1, sqrt(dx * dx + dy * dy) / radius)
            var angle = atan2(dy, dx) / (2 * .pi)
            if angle < 0 { angle += 1 }
            var next = grade
            if dist < 0.04 {
                next[keyPath: colorKey] = nil
                next[keyPath: amountKey] = 0
            } else {
                next[keyPath: colorKey] = Self.color(hue: angle)
                next[keyPath: amountKey] = dist
            }
            grade = next
        })
    }

    private static func color(hue: Double) -> GradeColor {
        let (r, g, b) = hsb(hue: hue, s: 1, v: 1)
        return GradeColor(red: r, green: g, blue: b)
    }

    private static func hue(r: Double, g: Double, b: Double) -> Double {
        let maxV = max(r, g, b), minV = min(r, g, b), d = maxV - minV
        guard d > 1e-6 else { return 0 }
        var h: Double
        if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxV == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        return h / 6
    }

    private static func hsb(hue: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let hh = (hue - floor(hue)) * 6
        let i = Int(hh), f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}

// MARK: - Black & White hue-band bar

/// Eight colored columns — drag each up to brighten that hue in the mono
/// conversion, down to darken it. Far cleaner than eight labeled sliders.
public struct HueBandBar: View {
    @Binding var grade: VideoGrade

    public init(grade: Binding<VideoGrade>) {
        self._grade = grade
    }

    private struct Band: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
        let keyPath: WritableKeyPath<VideoGrade, Double>
    }

    private let bands: [Band] = [
        Band(name: "R", color: .red, keyPath: \.bwRed),
        Band(name: "O", color: .orange, keyPath: \.bwOrange),
        Band(name: "Y", color: .yellow, keyPath: \.bwYellow),
        Band(name: "G", color: .green, keyPath: \.bwGreen),
        Band(name: "A", color: .cyan, keyPath: \.bwAqua),
        Band(name: "B", color: .blue, keyPath: \.bwBlue),
        Band(name: "P", color: .purple, keyPath: \.bwPurple),
        Band(name: "M", color: Color(red: 1, green: 0.3, blue: 0.9), keyPath: \.bwMagenta),
    ]

    public var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(bands) { band in
                bandColumn(band)
            }
        }
        .frame(height: 96)
    }

    private func bandColumn(_ band: Band) -> some View {
        let value = grade[keyPath: band.keyPath] // -1…1
        return GeometryReader { geo in
            let h = geo.size.height
            let mid = h / 2
            let knobY = mid - CGFloat(value) * (h / 2 - 6)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [band.color, .black], startPoint: .top, endPoint: .bottom))
                    .opacity(0.85)
                Rectangle().fill(.white.opacity(0.4)).frame(height: 1).offset(y: mid)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white)
                    .frame(height: 4)
                    .padding(.horizontal, 2)
                    .offset(y: knobY - 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let v = Double((mid - drag.location.y) / (h / 2 - 6))
                grade[keyPath: band.keyPath] = max(-1, min(1, v))
            })
            .overlay(alignment: .bottom) {
                Text(band.name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).padding(.bottom, 2)
            }
        }
    }
}

// MARK: - 12-band HSL editor

/// The pro HSL tool: 12 hue chips, and Hue / Saturation / Luminance sliders for
/// whichever band you pick. Kept behind an "advanced" disclosure by hosts.
public struct HSLEditor: View {
    @Binding var grade: VideoGrade
    @State private var band = 0

    public init(grade: Binding<VideoGrade>) {
        self._grade = grade
    }

    private var bands: [HSLBand] {
        let existing = grade.hslBands ?? []
        return existing.count == 12 ? existing : Array(repeating: HSLBand(), count: 12)
    }

    private func update(_ index: Int, _ mutate: (inout HSLBand) -> Void) {
        var arr = bands
        mutate(&arr[index])
        grade.hslBands = arr.allSatisfy { $0.isIdentity } ? nil : arr
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hue: Double(i) / 12, saturation: 0.85, brightness: 0.9))
                        .frame(height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(.white, lineWidth: band == i ? 2 : 0)
                        )
                        .overlay(alignment: .topTrailing) {
                            if !bands[i].isIdentity {
                                Circle().fill(.white).frame(width: 4, height: 4).padding(1)
                            }
                        }
                        .onTapGesture { band = i }
                }
            }
            let current = bands[band]
            GradientSlider(
                title: "Hue", value: Binding(
                    get: { CGFloat(current.hue) },
                    set: { v in update(band) { $0.hue = Double(v) } }
                ),
                range: -1...1,
                colors: [Color(hue: max(0, Double(band) / 12 - 0.08), saturation: 0.8, brightness: 0.9),
                         Color(hue: Double(band) / 12, saturation: 0.8, brightness: 0.9),
                         Color(hue: min(1, Double(band) / 12 + 0.08), saturation: 0.8, brightness: 0.9)],
                format: "%.2f", resetValue: 0
            )
            GradientSlider(
                title: "Saturation", value: Binding(
                    get: { CGFloat(current.sat) },
                    set: { v in update(band) { $0.sat = Double(v) } }
                ),
                range: -1...1,
                colors: [.gray, Color(hue: Double(band) / 12, saturation: 1, brightness: 0.9)],
                format: "%.2f", resetValue: 0
            )
            GradientSlider(
                title: "Luminance", value: Binding(
                    get: { CGFloat(current.lum) },
                    set: { v in update(band) { $0.lum = Double(v) } }
                ),
                range: -1...1,
                colors: [.black, .white],
                format: "%.2f", resetValue: 0
            )
        }
    }
}

// MARK: - Levels ramp

/// A tonal ramp with three draggable stops: black point, midtone (gamma) and
/// white point — the classic Levels control instead of three sliders.
public struct LevelsBar: View {
    @Binding var grade: VideoGrade
    var histogram: [Float]

    public init(grade: Binding<VideoGrade>, histogram: [Float] = []) {
        self._grade = grade
        self.histogram = histogram
    }

    private var black: Double { grade.levelsBlack }
    private var white: Double { grade.levelsWhite }
    private var gamma: Double { grade.levelsGamma }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let w = geo.size.width
                let gammaPos = 0.5 - (log(max(0.05, gamma)) / log(2.5)) * 0.5
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Canvas { context, canvasSize in
                        guard histogram.count > 1 else { return }
                        var fill = Path()
                        fill.move(to: CGPoint(x: 0, y: canvasSize.height))
                        for (i, v) in histogram.enumerated() {
                            fill.addLine(to: CGPoint(x: CGFloat(i) / CGFloat(histogram.count - 1) * canvasSize.width, y: canvasSize.height - CGFloat(v) * canvasSize.height))
                        }
                        fill.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height))
                        fill.closeSubpath()
                        context.fill(fill, with: .color(.white.opacity(0.28)))
                    }
                    .allowsHitTesting(false)
                    handle(x: black * w, color: .black, label: "Black")
                    handle(x: (black + (white - black) * gammaPos) * w, color: .gray, label: "Mid")
                    handle(x: white * w, color: .white, label: "White")
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let f = Double(max(0, min(1, drag.location.x / w)))
                    let midX = black + (white - black) * gammaPos
                    let dB = abs(f - black), dW = abs(f - white), dM = abs(f - midX)
                    var next = grade
                    if dM <= dB && dM <= dW {
                        let span = max(0.001, white - black)
                        let rel = max(0.02, min(0.98, (f - black) / span))
                        next.levelsGamma = pow(2.5, (0.5 - rel) * 2)
                    } else if dB < dW {
                        next.levelsBlack = max(0, min(white - 0.02, f))
                    } else {
                        next.levelsWhite = min(1, max(black + 0.02, f))
                    }
                    grade = next
                })
            }
            .frame(height: 26)
            HStack {
                Text("Levels").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button {
                    var next = grade
                    next.levelsBlack = 0; next.levelsWhite = 1; next.levelsGamma = 1
                    grade = next
                } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
    }

    private func handle(x: CGFloat, color: Color, label: String) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 3, height: 26)
            .overlay(Rectangle().stroke(.white.opacity(0.7), lineWidth: 0.5))
            .offset(x: x - 1.5)
            .help(label)
    }
}
