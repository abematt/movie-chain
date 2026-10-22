//
//  HoloSticker.swift
//  movie-quiz
//
//  A holographic sticker stuck onto a card: iridescent foil that shifts colour
//  and catches a moving sheen as the phone tilts (the gyro, via `TiltMotion`),
//  with its bottom-trailing corner slightly peeled up to show the paper backing.
//  Only the light moves; the sticker itself stays stuck where it is.
//
//  Used for the dealt start's flag on the chain cards and the "new best" stamp on
//  game over. Reduce Motion, or no gyro (the simulator): the foil holds still.
//

import SwiftUI
import CoreMotion

// MARK: - Sticker

struct HoloSticker<Label: View>: View {
    /// Resting tilt on the card, like it was slapped on by hand.
    var rotation: Angle = .degrees(-6)
    /// How far the corner is peeled, as a fraction of the sticker's shorter side.
    /// The resting value is a slight lift; callers animate it down from a big
    /// peel to "press" the sticker on.
    var peel: CGFloat = 0.24
    /// A drop shadow only while the sticker is *off* the card (landing). Stuck
    /// down it's flat — 0 — so it reads as on the surface, not floating above it;
    /// the only shadow left is the curl's, under the peeled corner.
    var shadow: CGFloat = 0
    var corner: CGFloat = 6
    /// Seeds this sticker's scratches and specks, so each sticker has its own
    /// wear and keeps it between launches.
    var wearSeed: UInt64 = 1
    @ViewBuilder var label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || !TiltMotion.shared.isAvailable {
                // No gyro (the simulator) or Reduce Motion: a still sticker. A
                // real sticker never moves on its own — only the light on it
                // does, and with no tilt there is nothing to drive that.
                sticker(tilt: .zero)
            } else {
                sticker(tilt: TiltMotion.shared.tilt)
                    .onAppear { TiltMotion.shared.start() }
                    .onDisappear { TiltMotion.shared.stop() }
            }
        }
        .rotationEffect(rotation)
    }

    /// Round joins: the fold's corners are sharp (45°), and a mitred join there
    /// shoots a thin spike out past the corner.
    static var outline: StrokeStyle {
        StrokeStyle(lineWidth: Theme.Border.width, lineCap: .round, lineJoin: .round)
    }

    // Tilt drives the *light* only — the foil's colour and sheen. The sticker's
    // shape stays put: it is stuck to the card, and moving it read as floating.
    private func sticker(tilt: CGSize) -> some View {
        let shape = StickerShape(corner: corner, peel: peel)
        return label
            .foregroundStyle(Theme.Color.onAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background { HoloFoil(tilt: tilt).clipShape(shape) }
            // Wear over everything printed on the foil, label included.
            .overlay { StickerWear(seed: wearSeed, tilt: tilt).clipShape(shape) }
            .overlay { shape.stroke(Theme.Color.border, style: Self.outline) }
            .overlay { PeelFlap(peel: peel) }
            .background {
                if shadow > 0 {
                    shape.fill(Theme.Color.shadow).offset(x: shadow, y: shadow)
                }
            }
    }
}

// MARK: - Wear

/// Hairline scratches and a few specks of grime, so the sticker looks handled
/// rather than freshly printed. The scratches are bright — they catch the light —
/// and catch it more as the phone tilts. Deterministic per `seed`.
private struct StickerWear: View {
    let seed: UInt64
    let tilt: CGSize

    var body: some View {
        // Theme colours are main-actor values; read them here, not in the canvas.
        let grime = Theme.Color.shadow
        let glint = min(1, abs(tilt.width) + abs(tilt.height))
        Canvas { context, size in
            var rng = SeededRandom(seed: seed)
            // Scratches: short, mostly-diagonal hairlines.
            for _ in 0..<7 {
                let start = CGPoint(x: rng.next(in: 0...size.width), y: rng.next(in: 0...size.height))
                let length = rng.next(in: 5...(size.width * 0.45))
                let angle = rng.next(in: -0.9...(-0.3))
                var path = Path()
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x + cos(angle) * length,
                                         y: start.y + sin(angle) * length))
                context.stroke(path, with: .color(.white.opacity(0.35 + 0.4 * glint)),
                               lineWidth: rng.next(in: 0.4...0.8))
            }
            // Specks: tiny flecks of dirt, darker.
            for _ in 0..<12 {
                let r = rng.next(in: 0.3...0.8)
                let rect = CGRect(x: rng.next(in: 0...size.width), y: rng.next(in: 0...size.height),
                                  width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(grime.opacity(0.25)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// SplitMix64: a tiny deterministic generator, so a sticker's wear is the same
/// every time it's drawn.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &self)
    }
}

// MARK: - Foil

/// The iridescent face: a pastel sweep whose hue rotates with tilt, under a
/// bright sheen band that slides across as the light "moves".
private struct HoloFoil: View {
    let tilt: CGSize

    var body: some View {
        ZStack {
            LinearGradient(colors: Theme.Holo.colors,
                           startPoint: UnitPoint(x: -0.2 + tilt.width * 0.4, y: 0),
                           endPoint: UnitPoint(x: 1.2 + tilt.width * 0.4, y: 1))
                .hueRotation(.degrees(Double(tilt.width + tilt.height) * 70))
            LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0.30),
                .init(color: .white.opacity(0.75), location: 0.5),
                .init(color: .white.opacity(0), location: 0.70),
            ],
            startPoint: UnitPoint(x: -0.6 + tilt.width * 1.2, y: -0.2 + tilt.height),
            endPoint: UnitPoint(x: 1.0 + tilt.width * 1.2, y: 1.2 + tilt.height))
        }
    }
}

// MARK: - Shapes

/// A rounded rectangle whose bottom-trailing corner is folded back along a
/// diagonal — the part of the sticker that has lifted off.
struct StickerShape: Shape {
    var corner: CGFloat
    /// Fraction of the shorter side that is peeled.
    var peel: CGFloat

    var animatableData: CGFloat {
        get { peel }
        set { peel = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = min(corner, w / 2, h / 2)
        let c = min(max(peel, 0) * min(w, h), min(w, h))
        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: h), radius: r)
        p.addLine(to: CGPoint(x: w, y: h - c))
        p.addLine(to: CGPoint(x: w - c, y: h))
        p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: 0), radius: r)
        p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: w, y: 0), radius: r)
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The lifted corner, folded over: the triangle the peeled-off corner makes when
/// it is reflected across the fold line, showing the sticker's paper backing.
private struct FlapShape: Shape {
    var peel: CGFloat

    var animatableData: CGFloat {
        get { peel }
        set { peel = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let c = min(max(peel, 0) * min(w, h), min(w, h))
        var p = Path()
        guard c > 0.5 else { return p }
        p.move(to: CGPoint(x: w, y: h - c))
        p.addLine(to: CGPoint(x: w - c, y: h))
        p.addLine(to: CGPoint(x: w - c, y: h - c))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private struct PeelFlap: View {
    let peel: CGFloat

    var body: some View {
        FlapShape(peel: peel)
            // Paper backing, shaded toward the fold so it reads as curling.
            .fill(LinearGradient(colors: [Theme.Color.tile, Theme.Color.hairline],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                FlapShape(peel: peel).stroke(Theme.Color.border,
                                             style: StrokeStyle(lineWidth: Theme.Border.width,
                                                                lineCap: .round, lineJoin: .round))
            }
            // The one soft shadow in the app: the curl lifting off the foil.
            .shadow(color: Theme.Color.shadow.opacity(0.35), radius: 1.5, x: -1, y: -1)
    }
}

// MARK: - The dealt start's flag

/// The small holographic "START" flag stuck on the dealt start's card.
struct StartSticker: View {
    var body: some View {
        HoloSticker(rotation: .degrees(-5), wearSeed: 7) {
            HStack(spacing: 4) {
                Image(systemName: "flag.checkered")
                Text("Start")
            }
            .font(Theme.Font.labelSmall)
            .textCase(.uppercase)
            .tracking(Theme.Font.labelSmallTracking)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start")
    }
}

// MARK: - Tilt

/// The phone's tilt from the gyro, shared by every sticker on screen. Runs only
/// while at least one sticker is showing. Tilt is measured relative to how the
/// phone is being held (a slowly adapting baseline), so it reacts to *changes*
/// in angle whether you're sitting up or lying down.
@MainActor @Observable
final class TiltMotion {
    static let shared = TiltMotion()

    /// Roughly −1…1 on each axis: `width` = side to side, `height` = toward/away.
    private(set) var tilt: CGSize = .zero

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var baseline: CGSize?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }
            let x = gravity.x, y = gravity.y
            // Delivered on the main queue, as requested above.
            MainActor.assumeIsolated { self?.update(x: x, y: y) }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
        baseline = nil
        tilt = .zero
    }

    private func update(x: Double, y: Double) {
        let raw = CGSize(width: x, height: y)
        var base = baseline ?? raw
        // Drift the resting angle toward the current one, slowly, so a held angle
        // becomes "level" after a few seconds.
        base.width += (raw.width - base.width) * 0.02
        base.height += (raw.height - base.height) * 0.02
        baseline = base
        let gain: CGFloat = 3
        let target = CGSize(width: clamp((raw.width - base.width) * gain),
                            height: clamp((raw.height - base.height) * gain))
        // Light smoothing so sensor jitter doesn't shimmer the foil.
        tilt = CGSize(width: tilt.width + (target.width - tilt.width) * 0.3,
                      height: tilt.height + (target.height - tilt.height) * 0.3)
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(1, max(-1, v)) }
}

#Preview("Stickers") {
    VStack(spacing: 40) {
        StartSticker()
        HoloSticker(rotation: .degrees(-8), peel: 0.22, wearSeed: 21) {
            VStack(spacing: 0) {
                Text("New best!").font(Theme.Font.heading(.title3))
                Text("was 7").font(Theme.Font.flourish(.footnote))
            }
            .padding(.horizontal, 4)
        }
    }
    .padding(40)
    .background(Theme.Color.canvas)
}
