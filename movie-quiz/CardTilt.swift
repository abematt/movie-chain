//
//  CardTilt.swift
//  movie-quiz
//
//  The tilt a lifted Reel card is drawn at: the phone's (the gyro, via
//  `TiltMotion`) plus a finger's (a drag), scaled by `intensity` so the card is
//  flat whenever it is flying to or from its grid slot.
//
//  `value` changes every display frame, so only small leaf views read it — the
//  foil, the photo's parallax, the glare, the rotation, the table shadow. The
//  card itself gets the object through the environment and never reads it, so a
//  tilt frame never re-runs the card's body. Everything here moves on one clock
//  (`DisplayLink`) with hand-sampled springs: a SwiftUI animation on any of it
//  would be cancelled by the next frame's gyro write.
//

import SwiftUI

@MainActor @Observable
final class CardTilt {
    /// Roughly −1…1 on each axis: `width` = side to side, `height` = toward/away.
    var value: CGSize {
        let g = gyroOn ? TiltMotion.shared.tilt : .zero
        let w = clamp(g.width + drag.width)
        let h = clamp(g.height + drag.height)
        return CGSize(width: w * intensity, height: h * intensity)
    }

    /// A finger's contribution, −1…1 each axis.
    private(set) var drag: CGSize = .zero
    private(set) var intensity: CGFloat = 0

    @ObservationIgnored private var gyroOn = false
    @ObservationIgnored private var ramp: (from: CGFloat, to: CGFloat, spring: Spring, elapsed: Double)?
    /// Where the drag was when the finger touched down, so grabbing a card
    /// mid-swing carries on from there instead of jumping.
    @ObservationIgnored private var grabbedAt: CGSize?
    @ObservationIgnored private var release: (from: CGSize, velocity: CGSize, elapsed: Double)?
    @ObservationIgnored private lazy var frames = DisplayLink { [weak self] dt in self?.advance(dt) }

    /// Points of finger travel for a full tilt.
    private static let reach: CGFloat = 120

    func start() {
        guard !gyroOn, TiltMotion.shared.isAvailable else { return }
        gyroOn = true
        TiltMotion.shared.start()
    }

    func stop() {
        frames.stop()
        ramp = nil
        release = nil
        grabbedAt = nil
        if gyroOn {
            TiltMotion.shared.stop()
            gyroOn = false
        }
    }

    /// Ease the tilt in (`true`) or flat (`false`), from wherever it is now.
    func setActive(_ active: Bool) {
        let to: CGFloat = active ? 1 : 0
        guard intensity != to || ramp != nil else { return }
        ramp = (intensity, to, active ? Theme.Motion.tiltIn : Theme.Motion.tiltOut, 0)
        frames.start()
    }

    /// The finger moved: tilt by how far it has gone since it touched down.
    func dragChanged(_ translation: CGSize) {
        release = nil
        let start = grabbedAt ?? drag
        grabbedAt = start
        drag = CGSize(width: clamp(start.width + translation.width / Self.reach),
                      height: clamp(start.height + translation.height / Self.reach))
    }

    /// The finger lifted: swing back level, carrying its speed.
    func dragEnded(velocity: CGSize) {
        grabbedAt = nil
        release = (drag, CGSize(width: velocity.width / Self.reach,
                                height: velocity.height / Self.reach), 0)
        frames.start()
    }

    private func advance(_ dt: Double) {
        if var r = ramp {
            r.elapsed += dt
            if r.elapsed >= r.spring.settlingDuration {
                intensity = r.to
                ramp = nil
            } else {
                let t = CGFloat(r.spring.value(target: 1.0, time: r.elapsed))
                intensity = r.from + (r.to - r.from) * t
                ramp = r
            }
        }
        if var r = release {
            r.elapsed += dt
            let spring = Theme.Motion.tiltRelease
            if r.elapsed >= spring.settlingDuration {
                drag = .zero
                release = nil
            } else {
                // The spring samples the offset (drag − from), which heads to
                // −from and starts at the finger's own velocity.
                let w = spring.value(target: Double(-r.from.width),
                                     initialVelocity: Double(r.velocity.width), time: r.elapsed)
                let h = spring.value(target: Double(-r.from.height),
                                     initialVelocity: Double(r.velocity.height), time: r.elapsed)
                drag = CGSize(width: r.from.width + w, height: r.from.height + h)
                release = r
            }
        }
        if ramp == nil, release == nil { frames.stop() }
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(1, max(-1, v)) }
}

extension EnvironmentValues {
    /// The lifted card's tilt; `nil` everywhere else (the grid, Reduce Motion).
    @Entry var cardTilt: CardTilt? = nil
}

/// Tips the card toward the tilt. Applied outside the flip, so the card turns
/// over on its own axis, and inside the flight, so it flies flat.
struct CardTiltRotation: ViewModifier {
    @Environment(\.cardTilt) private var tilt

    /// The most the card tips on each axis.
    private static let maxDegrees: Double = 8

    func body(content: Content) -> some View {
        let t = tilt?.value ?? .zero
        content
            .rotation3DEffect(.degrees(Double(t.width) * Self.maxDegrees),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(Double(-t.height) * Self.maxDegrees),
                              axis: (x: 1, y: 0, z: 0), perspective: 0.5)
    }
}
