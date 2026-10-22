//
//  Duotone.swift
//  movie-quiz
//
//  An actor card's photo is printed in two inks: its shadows in a deep shade
//  and its highlights in a pastel, one of the holo foil's own colours. Each
//  actor keeps the same pair everywhere (picked from their TMDB id), so a card
//  reads as *theirs*.
//
//  The tint is baked into the image once, off the main actor, when the art
//  loads (`ArtCache.load(_:duotone:)`), and cached like any other art: nothing
//  is computed per frame, and there's no mask or blend mode to push a tilting
//  card offscreen.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

nonisolated struct Duotone: Hashable, Sendable {
    /// Position in `palette`; also the cache key's suffix.
    let index: Int
    /// The shadows' ink, sRGB 0…1.
    let dark: (Double, Double, Double)
    /// The highlights' ink — a pastel, also a pastel card's face.
    let light: (Double, Double, Double)

    static func == (a: Duotone, b: Duotone) -> Bool { a.index == b.index }
    func hash(into hasher: inout Hasher) { hasher.combine(index) }

    /// The foil's five pastels (`Theme.Holo.colors`), each with a deep shade of
    /// its own hue for the shadows.
    static let palette: [Duotone] = [
        // Shadows are a mid-deep shade, not near-black: a face in a dark photo
        // still reads as coloured rather than muddy.
        Duotone(index: 0, dark: (0.50, 0.16, 0.40), light: (1.00, 0.76, 0.92)),  // pink
        Duotone(index: 1, dark: (0.30, 0.22, 0.62), light: (0.84, 0.78, 1.00)),  // lilac
        Duotone(index: 2, dark: (0.05, 0.33, 0.47), light: (0.72, 0.93, 1.00)),  // cyan
        Duotone(index: 3, dark: (0.07, 0.38, 0.27), light: (0.76, 0.97, 0.85)),  // mint
        Duotone(index: 4, dark: (0.55, 0.33, 0.06), light: (1.00, 0.95, 0.70)),  // lemon
    ]

    /// An actor's pair: fixed by their TMDB id, so it never changes between
    /// launches or devices.
    static func forActor(tmdbID: Int) -> Duotone {
        palette[((tmdbID % palette.count) + palette.count) % palette.count]
    }

    /// The image re-inked: luminance mapped from `dark` to `light`, with a touch
    /// more contrast so the two inks separate. `nil` if CoreImage can't render it.
    func apply(to image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let flat = CIFilter.colorControls()
        flat.inputImage = input
        flat.saturation = 0
        flat.contrast = 1.1
        let ink = CIFilter.falseColor()
        ink.inputImage = flat.outputImage
        ink.color0 = Self.ciColor(dark)
        ink.color1 = Self.ciColor(light)
        guard let output = ink.outputImage else { return nil }
        return Self.context.createCGImage(output, from: input.extent)
    }

    private static func ciColor(_ c: (Double, Double, Double)) -> CIColor {
        CIColor(red: c.0, green: c.1, blue: c.2, alpha: 1,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) ?? CIColor(red: c.0, green: c.1, blue: c.2)
    }

    /// One context for every render: making one per image costs more than the
    /// render. CIContext is Sendable: safe to share across threads.
    private static let context = CIContext(options: [.cacheIntermediates: false])
}

extension Duotone {
    var darkColor: Color { Color(.sRGB, red: dark.0, green: dark.1, blue: dark.2) }
    var lightColor: Color { Color(.sRGB, red: light.0, green: light.1, blue: light.2) }
}
