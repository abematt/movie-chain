//
//  DisplayLink.swift
//  movie-quiz
//
//  A display-synced frame callback, for motion SwiftUI animations can't drive:
//  a live sensor smoothed by elapsed time, or a spring sampled by hand so a
//  per-frame write elsewhere can never cancel it.
//

import QuartzCore

/// Calls `onFrame` with the seconds since the last frame, every display frame,
/// between `start` and `stop`. A running link retains this object, so always
/// pair them.
final class DisplayLink: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private let onFrame: (_ dt: Double) -> Void

    init(onFrame: @escaping (_ dt: Double) -> Void) {
        self.onFrame = onFrame
    }

    var isRunning: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Up to 120Hz on ProMotion; the tilt reads stepped below 60.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        last = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        // First frame, or back from a stall: a nominal step, never a leap.
        let dt = last.map { min(now - $0, 1.0 / 30) } ?? 1.0 / 60
        last = now
        onFrame(dt)
    }
}
