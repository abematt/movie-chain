# 005 — Drag to tilt the lifted card (and spring back with the flick)

- **Status**: DONE
- **Commit**: 8f02df1
- **Depends on**: 001 (`DisplayLink`), 003 (`CardTilt.drag`, `\.cardTilt`)
- **Severity**: MEDIUM
- **Category**: Interruptibility (+ missed opportunity: no gyro → a dead card)
- **Estimated scope**: `CardTilt.swift`, `ReelCards.swift`, `Theme.swift`; ~70 lines

## Problem

With no gyro (simulator, some iPads), or with the phone held still, the lifted
card can't be moved at all. Tilting a card with a finger is also the first thing
people try. Today the faces only take a tap (to flip):

```swift
// movie-quiz/ReelCards.swift:322-324 — current (after plan 004 it sits inside a ZStack)
faces
    .contentShape(Rectangle())
    .onTapGesture(perform: toggle)
```

## Target

- A `DragGesture(minimumDistance: 4)` on the faces, attached with
  `.simultaneousGesture`, so a tap still flips and a drag tilts.
- While dragging: `drag = clamp(grabbedAt + translation / 120)` per axis (±1), where
  `grabbedAt` is the drag value at the moment the finger went down. Grabbing a
  card mid-spring therefore continues from where it is — no jump.
- On release: spring `drag` back to zero on the display clock with
  `Theme.Motion.tiltRelease = Spring(duration: 0.5, bounce: 0.15)`, seeded with the
  gesture's release velocity (`value.velocity / 120`, per axis). A flick
  overshoots slightly and settles; a slow release just eases home.
- The gyro and the drag add together (already the case in `CardTilt.value`), so
  you can drag while the phone moves.
- Reduce Motion: no `CardTilt`, so the gesture does nothing (guard on `tilt == nil`).
- No SwiftUI animation on `drag` — gyro writes every frame would cancel it. The
  spring is sampled by hand, like `intensity` in plan 003.

## Repo conventions to follow

- Springs sampled by hand: `Theme.Motion.handoffSpring.value(target:time:)`
  (`Handoff.swift:177`) and `CardTilt.advance` from plan 003.
- New spring goes in `Theme.Motion` next to `tiltIn`/`tiltOut`, with a `///` line.

## Steps

1. **`Theme.swift`** (`enum Motion`, after `tiltOut`):
   ```swift
   /// A dragged card swinging back level when let go — carries the flick, with a
   /// small settle (playful object, so a touch of bounce).
   static let tiltRelease = Spring(duration: 0.5, bounce: 0.15)
   ```

2. **`CardTilt.swift`:**
   - Make `drag` `private(set)`.
   - Add state:
     ```swift
     @ObservationIgnored private var grabbedAt: CGSize?
     @ObservationIgnored private var release: (from: CGSize, velocity: CGSize, elapsed: Double)?
     /// Points of finger travel for a full tilt.
     private static let reach: CGFloat = 120
     ```
   - Add:
     ```swift
     /// The finger moved: tilt by how far it has gone since it touched down.
     func dragChanged(_ translation: CGSize) {
         release = nil
         let start = grabbedAt ?? drag
         grabbedAt = start
         drag = CGSize(width: min(1, max(-1, start.width + translation.width / Self.reach)),
                       height: min(1, max(-1, start.height + translation.height / Self.reach)))
     }

     /// The finger lifted: swing back level, carrying its speed.
     func dragEnded(velocity: CGSize) {
         grabbedAt = nil
         release = (drag, CGSize(width: velocity.width / Self.reach,
                                 height: velocity.height / Self.reach), 0)
         frames.start()
     }
     ```
   - In `advance(_:)`, handle `release` alongside `ramp`. Keep the link running while
     **either** is active; stop it only when both are nil:
     ```swift
     if var r = release {
         r.elapsed += dt
         // The spring runs from `from` to zero. It samples the offset (drag − from),
         // which heads to −from and moves at the drag's own velocity.
         let s = Theme.Motion.tiltRelease
         let w = s.value(target: -r.from.width, initialVelocity: r.velocity.width, time: r.elapsed)
         let h = s.value(target: -r.from.height, initialVelocity: r.velocity.height, time: r.elapsed)
         drag = CGSize(width: r.from.width + w, height: r.from.height + h)
         if r.elapsed >= s.settlingDuration { drag = .zero; release = nil } else { release = r }
     }
     ```
     Restructure the existing ramp branch so it no longer `return`s/stops the link
     early; end `advance` with `if ramp == nil && release == nil { frames.stop() }`.
     Check the sign of `initialVelocity` in the feel check: a flick to the right must
     keep the card tipping right for a moment before it swings back. If it snaps
     back immediately instead, negate the velocity terms — the only permitted tweak.
     If `Spring.value(target:initialVelocity:time:)` doesn't compile with `Double`,
     STOP and report.
   - `stop()` also clears `release` and `grabbedAt`.

3. **`ReelCards.swift`, `ReelCardDetail`** — on `faces`, right after
   `.onTapGesture(perform: toggle)`:
   ```swift
   .simultaneousGesture(
       DragGesture(minimumDistance: 4)
           .onChanged { value in tilt?.dragChanged(value.translation) }
           .onEnded { value in tilt?.dragEnded(velocity: value.velocity) }
   )
   ```
   No `@State`/`@GestureState` for the drag — it lives in `CardTilt`, so only the
   tilt leaves re-run while dragging.

## Boundaries

- Do NOT add a drag to dismiss, or any drag on the backdrop — tilt only.
- Do NOT animate `drag` with `withAnimation`.
- Do NOT change `reach` (120), the clamp, or the spring values except the one
  sign tweak above.
- Movie frames: no gesture (`tilt` is nil for them, so the guard covers it).

## Verification

- **Mechanical**: `python3 scripts/swift-check.py` clean; CLAUDE.md test command green.
- **Feel check (simulator is fine for this one):**
  - `-uiDemoReel -uiOpenReel`, lift an actor card. A tap still flips it. A short
    drag tips it under the finger (card, glare, parallax, shadow all respond).
  - Let go slowly: eases level with no bounce to speak of.
  - Flick: tips further in the flick direction, overshoots slightly past level,
    settles. Grab it again mid-swing — it continues from where it is, no jump.
  - Drag, then hit Close while still dragging or swinging: the card still flattens
    and lands on its slot cleanly (intensity → 0 multiplies the drag out).
  - Real iPhone: drag and tilt the phone at once — the effects add up and stay
    within ±8°.
  - Reduce Motion: dragging does nothing; tap still flips (cross-fade).
- **Done when**: tap and drag coexist, the release carries the flick, re-grabbing
  never jumps, and closing mid-drag still lands seamlessly.
