//
//  Sound.swift
//  movie-quiz
//
//  A tiny synthesised sound layer. Rather than bundle audio assets, we generate
//  short sine-wave tones on the fly with AVAudioEngine. Each correct link chimes a
//  note from a major-pentatonic scale, *cycling within a single octave* so the
//  pitch varies pleasantly link-to-link but never climbs ever-higher into a
//  shrill register on a long chain. Wrong answers get a short low buzz.
//
//  Uses the `.ambient` audio session category on iOS so the game mixes with
//  other audio and honours the ringer/silent switch — muted phone, no chime.
//  All failures degrade silently to "no sound"; audio is pure polish.
//

import Foundation
import AVFoundation

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private let format: AVAudioFormat
    private var started = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Spin the audio engine up ahead of the first chime so it lands in sync with
    /// the haptic and the tile drop. Without this, the first `correct()` of a run
    /// pays engine-start + session-activation latency and the chime arrives late,
    /// breaking the visual/sound/haptic harmony a correct link should have.
    func warm() { startIfNeeded() }

    private func startIfNeeded() {
        guard !started else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            started = false
        }
    }

    /// A chime for a correct link. `streak` (chain length) picks a note from a
    /// major-pentatonic scale, cycling *within one octave* so consecutive links
    /// vary in pitch without the run climbing ever higher into a shrill register.
    func correct(streak: Int) {
        let scale = [0, 2, 4, 7, 9]                     // major pentatonic, semitones
        let semitone = scale[max(0, streak - 1) % scale.count]
        let frequency = 523.25 * pow(2.0, Double(semitone) / 12.0)   // C5 .. A5
        play(frequency: frequency, duration: 0.18)
    }

    /// A short low buzz for a wrong answer.
    func wrong() {
        play(frequency: 160, duration: 0.22)
    }

    // MARK: Synthesis

    private func play(frequency: Double, duration: Double) {
        startIfNeeded()
        guard started else { return }

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard
            frameCount > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channel = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = frameCount

        let count = Int(frameCount)
        let attack = 0.008                              // seconds
        let decay = 6.0 / duration                      // exp fall-off across the note
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = min(1.0, t / attack) * exp(-t * decay)
            channel[i] = Float(sin(2.0 * .pi * frequency * t) * envelope * 0.28)
        }

        // `.interrupts` so rapid answers cut the previous tone instead of piling up.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }
}
