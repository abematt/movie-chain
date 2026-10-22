# 002 — Move the holo foil by transform, not by gradient geometry

- **Status**: DONE
- **Commit**: 8f02df1
- **Severity**: HIGH
- **Category**: Performance
- **Estimated scope**: 1 file (`HoloSticker.swift`), ~40 lines

## Problem

`HoloFoil` animates by changing each gradient's `startPoint`/`endPoint` from
`tilt`. Every tilt frame therefore produces a *different gradient* that has to be
re-rasterised (paint tier) instead of the same pixels being moved (composite
tier). Today that's 30×/s on a sticker; after plan 001 it's up to 120×/s, and
after plan 003 the foil covers a whole lifted card.

```swift
// movie-quiz/HoloSticker.swift:147-166 — current
struct HoloFoil: View {
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
```

## Target

Both gradients are drawn **once, oversized, with fixed geometry**, and only an
`offset` (transform) and the existing `hueRotation` (a GPU colour filter) change
with tilt. The visual matches today's: the colour sweep slides 0.4 × width per
unit tilt; the sheen band slides 1.2 × width and 1.0 × height per unit tilt.

```swift
// target
struct HoloFoil: View {
    let tilt: CGSize

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // The colour sweep, three times the foil's size so a full tilt
                // never shows its edge. Drawn once; tilt only slides it.
                LinearGradient(colors: Theme.Holo.colors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: w * 3, height: h * 3)
                    .offset(x: tilt.width * w * 0.4)
                    .hueRotation(.degrees(Double(tilt.width + tilt.height) * 70))
                // The sheen: a fixed diagonal band the light slides across.
                LinearGradient(stops: [
                    .init(color: .white.opacity(0), location: 0.40),
                    .init(color: .white.opacity(0.75), location: 0.5),
                    .init(color: .white.opacity(0), location: 0.60),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: w * 3, height: h * 3)
                    .offset(x: tilt.width * w * 1.2, y: tilt.height * h)
            }
            .frame(width: w, height: h)
        }
        .clipped()
    }
}
```

The sheen band's stops narrow from 0.30/0.5/0.70 to 0.40/0.5/0.60 because the
gradient now spans 3× the area; that keeps the band the same on-card width.
Confirm by eye against `main` (see Verification) and adjust only these two
stop values if the band reads wider/narrower than before.

## Repo conventions to follow

- Comments say *why*, briefly, as in the rest of `HoloSticker.swift`.
- Don't reach for `visualEffect` here: it would need a `@Sendable` capture list and
  buys nothing over `offset` inside the `GeometryReader`.

## Steps

1. Replace the body of `HoloFoil` (`movie-quiz/HoloSticker.swift:147-166`) with the
   target above. Keep the type name, its `let tilt: CGSize` API and its doc
   comment (update the comment's last clause to "…under a bright sheen band; tilt
   slides both, it never redraws them").
2. Build and run the checks below.

## Boundaries

- Do NOT change `Theme.Holo.colors`, the 70° hue factor, or `HoloFoil`'s API.
- Do NOT touch `StickerWear` (its `Canvas` redraws on tilt by design and is tiny).
- Do NOT add `drawingGroup()`.

## Verification

- **Mechanical**: `python3 scripts/swift-check.py` clean; the test command in
  CLAUDE.md green.
- **Feel check:**
  - In the `#Preview("Stickers")` canvas and on game over, the stickers look the
    same as on `main` at rest (tilt zero): same colour order, sheen across the middle.
  - Temporarily hardcode `HoloFoil(tilt: CGSize(width: 1, height: 0))` in the
    preview, compare with `main` at the same value: the sweep and sheen sit in
    the same place (±a few pt). Revert the hardcode.
  - Real device: tilt fully left/right — no transparent edge ever shows inside
    the sticker.
  - Instruments → Core Animation, "Color Offscreen-Rendered" / Time Profiler: the
    gradient isn't re-rasterised per frame (no `LinearGradient` render samples
    while only tilting).
- **Done when**: visuals match `main`, edges never show, and tilting no longer
  shows gradient rendering in the profile.
