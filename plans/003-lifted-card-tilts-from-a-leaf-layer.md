# 003 — The lifted actor card tilts in 3D, driven from leaf views only

- **Status**: DONE
- **Commit**: 8f02df1
- **Depends on**: 001 (`DisplayLink`, display-clock `TiltMotion`), 002 (transform-only `HoloFoil`)
- **Severity**: HIGH
- **Category**: Performance + Interruptibility (+ the new tilt feature itself)
- **Estimated scope**: 1 new file (`CardTilt.swift`), edits to `ReelCards.swift`; ~200 lines

## Problem

Three things in today's code have to be right before the lifted card can move in 3D.

**(a) Per-frame invalidation of the whole card.** The live holo card hands
the gyro value into `ReelActorCard`, so every tilt sample re-runs the entire card
body: the `VStack`, `Text`, a 10-pip `ForEach`, `neoSurface`, and `ReelArt.init`
(two `ArtCache` lookups). This is the SwiftUI form of "setState every frame".

```swift
// movie-quiz/ReelCards.swift:460-467 — current
private struct LiveHoloActorCard: View {
    let entity: CollectedEntity

    var body: some View {
        ReelActorCard(entity: entity, tilt: TiltMotion.shared.tilt, sharpArt: true)
            .onAppear { TiltMotion.shared.start() }
            .onDisappear { TiltMotion.shared.stop() }
    }
}
```
```swift
// movie-quiz/ReelCards.swift:95-109 — current (excerpt)
struct ReelActorCard: View {
    let entity: CollectedEntity
    /// Live tilt for the lifted card. The grid passes `.zero`, so a deck full of
    /// holo never runs the gyro.
    var tilt: CGSize = .zero
    ...
        case .holo:
            HoloFoil(tilt: tilt)
```

**(b) The flight needs a flat card.** `LiftFlight` lands the lifted card
pixel-for-pixel on its grid slot, and only then does `CollectionView` swap the grid
card back in. Any tilt left at take-off or landing turns that swap into a pop.

```swift
// movie-quiz/ReelCards.swift:321-329 — current
.overlay {
    faces
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .modifier(LiftFlight(progress: travels ? (out ? 1 : 0) : 1, from: slot, to: rest))
        .opacity(rest == nil ? 0 : travels ? 1 : (out ? 1 : 0))
}
```
```swift
// movie-quiz/CollectionView.swift:416-424 — current: the flight home
guard expanded != nil, !closing else { return }
withAnimation(reduceMotion ? Theme.Motion.reducedFade : Self.homeFlight) {   // .spring(duration: 0.38, bounce: 0)
    closing = true
    flipped = false
} completion: { ... }
```

**(c) Flip and tilt must not nest the wrong way.** `FlipView` already applies a
`rotation3DEffect` (y-axis, perspective 0.4). A tilt applied *inside* it would
make the flip turn around a tilted axis.

## Target

- A `CardTilt` object (one per lifted card) owns the **effective tilt**:
  `(gyro + drag) clamped to ±1, × intensity`. It is `@Observable`. The *reference*
  is injected through the environment; only small leaf views read `.value`, so a
  tilt frame only re-runs those leaves.
- `ReelActorCard` takes **no tilt parameter** and never reads tilt itself.
- Leaves:
  - `ReelFoil`: the holo face, `HoloFoil(tilt: cardTilt?.value ?? .zero)`.
  - `ReelParallax`: wraps the photo; `scaleEffect(1.08)` (constant) then
    `offset(x: -t.width * 2.5, y: -t.height * 2.5)` in design points (the canvas
    scales 110→240, so that's ~5.5 pt lifted).
  - `ReelGlare`: over the front of any lifted actor card (all finishes); a white
    diagonal band, `opacity(0.10 + 0.25 * magnitude)`, offset by tilt,
    `.blendMode(.plusLighter)`, no hit testing.
  - `CardTiltRotation` (`ViewModifier`): two `rotation3DEffect`s, ±8° each axis,
    perspective 0.5, applied **outside** `FlipView` and **inside** `LiftFlight`.
- `intensity` is driven on the display clock with `Spring`s (no SwiftUI animation
  on any tilt path, so per-frame gyro writes can never cancel it):
  - **in**: from 0 to 1 with `Spring(duration: 0.35, bounce: 0)`, started when the
    detail's existing `settled` flag turns on;
  - **out**: from current to 0 with `Spring(duration: 0.18, bounce: 0)`, started in
    the same call that sets `closing` — it finishes well inside the 0.38 s flight home.
- Reduce Motion, or a movie frame: no `CardTilt` is created; leaves read `nil` and
  draw flat. `ReelGlare` still shows its static band (opacity 0.10) on a lifted
  actor card under Reduce Motion — a still sheen, no movement.
- Grid cards: no `CardTilt` in their environment, no glare (`lifted == false`).

## Repo conventions to follow

- Environment values via `@Entry` — exemplar `movie-quiz/Handoff.swift:468-470`.
- Springs sampled by hand on an own clock — exemplar
  `Theme.Motion.handoffSpring.value(target: 1.0, time: elapsed)` at `Handoff.swift:177`.
  Add the two springs to `Theme.Motion` as `Spring` values next to
  `handoffSpring` (`Theme.swift:238`), named `tiltIn` and `tiltOut`, each with a
  one-line `///` comment saying what it is for.
- Main-actor by default; `@Sendable` closures copy captures; no `print(`;
  `scripts/swift-check.py` runs on every edit.

## Steps

1. **`movie-quiz/Theme.swift`** (in `enum Motion`, after `handoffSpring`):
   ```swift
   /// A lifted card's tilt coming alive once it has settled — gentle, unbouncy.
   static let tiltIn = Spring(duration: 0.35, bounce: 0)
   /// The tilt flattening as the card goes home; done well inside `homeFlight`
   /// so the card lands flat on its slot.
   static let tiltOut = Spring(duration: 0.18, bounce: 0)
   ```

2. **New file `movie-quiz/CardTilt.swift`:**
   ```swift
   import SwiftUI

   /// The tilt a lifted card is drawn at: the phone's (gyro) plus a finger's
   /// (drag, plan 005), scaled by `intensity` so the card is flat whenever it's
   /// flying to or from its grid slot. Read `value` only in small leaf views —
   /// it changes every display frame.
   @MainActor @Observable
   final class CardTilt {
       /// Roughly −1…1 each axis.
       var value: CGSize {
           let g = gyroOn ? TiltMotion.shared.tilt : .zero
           let w = min(1, max(-1, g.width + drag.width))
           let h = min(1, max(-1, g.height + drag.height))
           return CGSize(width: w * intensity, height: h * intensity)
       }

       /// A finger's contribution (plan 005 drives it). 0 until then.
       var drag: CGSize = .zero
       private(set) var intensity: CGFloat = 0

       @ObservationIgnored private var gyroOn = false
       @ObservationIgnored private var ramp: (from: CGFloat, to: CGFloat, spring: Spring, elapsed: Double)?
       @ObservationIgnored private lazy var frames = DisplayLink { [weak self] dt in self?.advance(dt) }

       func start() {
           guard !gyroOn, TiltMotion.shared.isAvailable else { return }
           gyroOn = true
           TiltMotion.shared.start()
       }

       func stop() {
           frames.stop()
           ramp = nil
           if gyroOn { TiltMotion.shared.stop(); gyroOn = false }
       }

       /// Ease the tilt in (`true`) or flat (`false`), from wherever it is now.
       func setActive(_ active: Bool) {
           let to: CGFloat = active ? 1 : 0
           guard intensity != to || ramp != nil else { return }
           ramp = (intensity, to, active ? Theme.Motion.tiltIn : Theme.Motion.tiltOut, 0)
           frames.start()
       }

       private func advance(_ dt: Double) {
           guard var r = ramp else { frames.stop(); return }
           r.elapsed += dt
           let t = CGFloat(r.spring.value(target: 1.0, time: r.elapsed))
           intensity = r.from + (r.to - r.from) * t
           if r.elapsed >= r.spring.settlingDuration {
               intensity = r.to
               ramp = nil
               frames.stop()
           } else {
               ramp = r
           }
       }
   }

   extension EnvironmentValues {
       /// The lifted card's tilt; `nil` everywhere else (the grid, Reduce Motion).
       @Entry var cardTilt: CardTilt? = nil
   }

   /// Tips the card toward the tilt. Applied outside the flip, so the card turns
   /// over on its own axis, and inside the flight, so it flies flat.
   struct CardTiltRotation: ViewModifier {
       @Environment(\.cardTilt) private var tilt

       func body(content: Content) -> some View {
           let t = tilt?.value ?? .zero
           content
               .rotation3DEffect(.degrees(Double(t.width) * 8), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
               .rotation3DEffect(.degrees(Double(-t.height) * 8), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
       }
   }
   ```
   If `Spring.settlingDuration` or `value(target:time:)` don't compile as written,
   STOP and report — check `Handoff.swift` for the form this repo already uses.

3. **`ReelCards.swift`, `ReelActorCard`:**
   - Delete `var tilt: CGSize = .zero` and its comment. Add
     `/// Lifted: the laminate glare that catches the light. Grid cards are matte.`
     `var lifted = false`.
   - Wrap the photo: `ReelParallax { ReelArt(...) }` — the existing `ReelArt`
     call and its modifiers stay as they are; put `ReelParallax` around `ReelArt`
     **before** `.frame(maxWidth:…)`/`.clipShape`, so the clip still trims the
     moved photo.
   - `face` `.holo` case: `ReelFoil()` instead of `HoloFoil(tilt: tilt)`.
   - After `.clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))` and
     **before** `.neoSurface(...)`, add
     `.overlay { if lifted { ReelGlare().clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm)) } }`.

4. **`ReelCards.swift`, add the leaves** (in the "Pieces" section):
   ```swift
   /// The holo face, lit by the lifted card's tilt. Its own view so a tilt
   /// frame redraws only the foil, not the card.
   private struct ReelFoil: View {
       @Environment(\.cardTilt) private var tilt
       var body: some View { HoloFoil(tilt: tilt?.value ?? .zero) }
   }

   /// The photo sitting a little behind the card's face: it slides against the
   /// tilt inside its window. Scaled up a touch so the slide never shows an edge.
   private struct ReelParallax<Content: View>: View {
       @Environment(\.cardTilt) private var tilt
       @ViewBuilder let content: Content
       var body: some View {
           let t = tilt?.value ?? .zero
           content
               .scaleEffect(1.08)
               .offset(x: -t.width * 2.5, y: -t.height * 2.5)
       }
   }

   /// Light catching the laminate on a lifted card: a soft diagonal band that
   /// brightens and slides as the card tips. Still (and faint) without tilt.
   private struct ReelGlare: View {
       @Environment(\.cardTilt) private var tilt
       var body: some View {
           let t = tilt?.value ?? .zero
           let magnitude = min(1, (abs(t.width) + abs(t.height)) / 1.4)
           GeometryReader { g in
               LinearGradient(stops: [
                   .init(color: .white.opacity(0), location: 0.40),
                   .init(color: .white, location: 0.5),
                   .init(color: .white.opacity(0), location: 0.60),
               ], startPoint: .topLeading, endPoint: .bottomTrailing)
                   .frame(width: g.size.width * 3, height: g.size.height * 3)
                   .offset(x: t.width * g.size.width * 0.8, y: t.height * g.size.height * 0.8)
                   .frame(width: g.size.width, height: g.size.height)
           }
           .opacity(0.10 + 0.25 * magnitude)
           .blendMode(.plusLighter)
           .allowsHitTesting(false)
       }
   }
   ```

5. **`ReelCards.swift`, `ReelCardDetail`:**
   - Add `@State private var tilt: CardTilt?` with the comment
     `/// The card's live tilt — actor cards only, never under Reduce Motion.`
   - Delete `private var live: Bool { … }` and `LiveHoloActorCard` entirely.
   - `front`: the actor branch becomes `ReelActorCard(entity: entity, sharpArt: true, lifted: true)`
     (one branch, no `live` check). Argument order follows the property order.
   - On `faces`, add `.modifier(CardTiltRotation())` **between**
     `.onTapGesture(perform: toggle)` and `.modifier(LiftFlight(...))`.
   - On the `VStack` in `body` (or the `card` view — anywhere enclosing `faces`),
     add `.environment(\.cardTilt, tilt)`.
   - Lifecycle (on the outer `ZStack` in `body`):
     ```swift
     .onAppear {
         guard isActor, !reduceMotion else { return }
         let t = CardTilt()
         t.start()
         tilt = t
     }
     .onDisappear { tilt?.stop() }
     .onChange(of: settled) { _, on in if on { tilt?.setActive(true) } }
     .onChange(of: closing) { _, on in if on { tilt?.setActive(false) } }
     ```
     `closing` flips inside `CollectionView`'s `withAnimation(homeFlight)`, so the
     ramp-out starts in the same frame as the flight home.

## Boundaries

- Do NOT touch `ReelFrame` (movies) — framed posters don't tilt in this plan.
- Do NOT change `LiftFlight`, `FlipView`, the open/flip/home springs, or the grid.
- Do NOT add `drawingGroup()`/`compositingGroup()` — only if a device recording
  shows dropped frames, and then as its own change.
- Do NOT change the card's built-in shadow here — plan 004 does that.
- If the code doesn't match the excerpts, STOP and report.

## Verification

- **Mechanical**: `python3 scripts/swift-check.py` clean; CLAUDE.md test command green.
  Simulator: `-uiDemoReel -uiOpenReel` opens a demo Reel; lift Keanu Reeves (holo)
  — no gyro, so the card must look exactly like `main` plus a faint static glare band.
- **Feel check (real iPhone):**
  - Lift any actor card: it flies out flat, then over ~⅓ s starts tipping with the
    phone (±8°). The photo drifts slightly against the tilt; the glare slides and
    brightens; on Keanu (holo) the foil shifts too.
  - Tilt hard, then tap Close: the card flattens in the first ~0.2 s of the flight
    and lands on its slot with **no pop** at the swap. Record at 240fps (or Xcode's
    slow animations) and step the last frames.
  - Flip while tilted: the card turns over on its own vertical axis, tipping
    with the phone on both faces.
  - Instruments → SwiftUI template, "View Body": while tilting, only
    `ReelFoil`/`ReelParallax`/`ReelGlare`/`CardTiltRotation` bodies update per
    frame — `ReelActorCard`, `ReelArt` and `ReelCardDetail` do not.
  - Settings → Accessibility → Reduce Motion on: the card fades in, never tips,
    shows a still glare.
- **Done when**: all of the above hold, and the grid never runs the gyro (no
  `CardTilt`/`advance` samples with nothing lifted).
