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
//  iOS stops the engine on its own — a call, Siri, AirPods connecting or
//  disconnecting, sometimes a trip to the background — without telling us. So
//  every sound asks the engine whether it is *actually* running and restarts it
//  if not, rather than trusting a flag set once at launch (which left the game
//  silent until relaunch after the first interruption).
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

    /// Whether the engine is up and the player node is rolling. Both are
    /// asked fresh: iOS can stop either behind our back.
    private var isReady: Bool { engine.isRunning && player.isPlaying }

    private func startIfNeeded() {
        guard !isReady else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        if !engine.isRunning {
            // A stopped engine resets its nodes; prepare before restarting.
            engine.prepare()
            try? engine.start()
        }
        if engine.isRunning, !player.isPlaying { player.play() }
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

    /// The record chime: two rising notes, a fourth apart, an octave above the
    /// correct-link register — the in-play "you just passed your best" beat.
    func record() {
        play(notes: [(1046.50, 0.12), (1396.91, 0.28)])   // C6 → F6
    }

    /// A short low buzz for a wrong answer.
    func wrong() {
        play(frequency: 160, duration: 0.22)
    }

    // MARK: Synthesis

    private func play(frequency: Double, duration: Double) {
        play(notes: [(frequency, duration)])
    }

    /// Synthesises a sequence of enveloped sine notes into one buffer, so a
    /// multi-note chime plays as a single unit (`.interrupts` on separate buffers
    /// would cut each note off with the next).
    private func play(notes: [(frequency: Double, duration: Double)]) {
        startIfNeeded()
        guard isReady else { return }

        let total = notes.reduce(0) { $0 + $1.duration }
        let frameCount = AVAudioFrameCount(sampleRate * total)
        guard
            frameCount > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channel = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = frameCount

        let attack = 0.008                              // seconds
        var offset = 0
        for note in notes {
            let count = Int(sampleRate * note.duration)
            let decay = 6.0 / note.duration             // exp fall-off across the note
            for i in 0..<count where offset + i < Int(frameCount) {
                let t = Double(i) / sampleRate
                let envelope = min(1.0, t / attack) * exp(-t * decay)
                channel[offset + i] = Float(sin(2.0 * .pi * note.frequency * t) * envelope * 0.28)
            }
            offset += count
        }

        // `.interrupts` so rapid answers cut the previous tone instead of piling up.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }
}
