# 004 — Give the lifted card a shadow on the table, not glued to the card

- **Status**: DONE
- **Commit**: 8f02df1
- **Depends on**: 003 (`CardTilt`, `\.cardTilt`, `ReelActorCard(lifted:)`, `CardTiltRotation`)
- **Severity**: HIGH
- **Category**: Physicality & origin
- **Estimated scope**: `ReelCards.swift` only; ~70 lines

## Problem

The card's neobrutalist hard shadow is drawn *inside* the card by `neoSurface`:

```swift
// movie-quiz/Components.swift:27-35 — current
content
    .background(shape.fill(fill))
    .overlay(shape.strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
    .background(shape.fill(Theme.Color.shadow).offset(x: depth, y: depth))
    .offset(x: shift, y: shift)
```
```swift
// movie-quiz/ReelCards.swift:131-132 — current
.clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
.neoSurface(radius: Theme.Radius.sm, fill: .clear, shadow: Theme.Shadow.small)
```
```swift
// movie-quiz/ReelCards.swift:413-415 — current: the back face
.background(Theme.Color.tile)
.clipShape(RoundedRectangle(cornerRadius: isActor ? Theme.Radius.md : 0))
.neoSurface(radius: isActor ? Theme.Radius.md : 0, fill: .clear, shadow: Theme.Shadow.large)
```

Once plan 003 rotates the card in 3D, that shadow rotates *with* it. It looks
painted onto the card instead of falling on the table, which kills the depth the
tilt exists for. While the card flips, a shadow that stays full width when the
card is edge-on also looks wrong.

## Target

On the **lifted actor card only**:

- The card and its back draw **no** built-in shadow (`shadow: 0`).
- `ReelCardDetail` draws one `TableShadow` underneath the faces, **outside**
  `CardTiltRotation` (so it never rotates) and **inside** `LiftFlight` (so it flies
  with the card).
- At zero tilt it is pixel-identical to the grid card's own shadow, scaled up:
  with `k = ReelLayout.liftedWidth / ReelLayout.designWidth`, it is
  `RoundedRectangle(cornerRadius: Theme.Radius.sm * k)` filled `Theme.Color.shadow`,
  offset `(Theme.Shadow.small * k, Theme.Shadow.small * k)`. That keeps the landing
  on the slot seamless (plan 003 flattens tilt before landing).
- Tilt moves it by **offset only** (a transform; no blur, never `.shadow(radius:)`):
  extra offset `(-t.width * 5, -t.height * 5)` points.
- During a flip it narrows with the card: `scaleEffect(x: max(0.02, abs(cos(angle))), y: 1)`,
  where `angle` animates with the same flip spring. Under Reduce Motion (cross-fade
  flip) the angle stays 0.

Movie frames keep their built-in shadow; the grid is unchanged.

## Repo conventions to follow

- Hard, unblurred shadows only — `Theme.swift:71` ("Shadows are solid, unblurred").
- Animatable shapes/effects declare `animatableData` explicitly — exemplar
  `FlipView` at `ReelCards.swift:473-493`.

## Steps

1. **`ReelActorCard`:** change the `neoSurface` call to
   `.neoSurface(radius: Theme.Radius.sm, fill: .clear, shadow: lifted ? 0 : Theme.Shadow.small)`
   and extend the `lifted` doc comment: "…and its shadow falls on the table
   (`TableShadow`), not on the card."

2. **`ReelCardDetail.back`:** change the last line to
   `.neoSurface(radius: isActor ? Theme.Radius.md : 0, fill: .clear, shadow: isActor ? 0 : Theme.Shadow.large)`.
   (A movie's back keeps its shadow; it has no table shadow.)

3. **Add to `ReelCards.swift`** (next to `FlipView`):
   ```swift
   /// The lifted card's shadow, cast on the table rather than printed on the
   /// card: it stays flat while the card tips, slides away from the tilt, and
   /// narrows as the card turns edge-on. At rest it matches the grid card's own
   /// shadow exactly, so the card lands on its slot without a seam.
   private struct TableShadow: View, Animatable {
       /// The flip's angle, animated by the same spring as the flip.
       var angle: Double
       @Environment(\.cardTilt) private var tilt

       var animatableData: Double {
           get { angle }
           set { angle = newValue }
       }

       var body: some View {
           let k = ReelLayout.liftedWidth / ReelLayout.designWidth
           let rest = Theme.Shadow.small * k
           let t = tilt?.value ?? .zero
           RoundedRectangle(cornerRadius: Theme.Radius.sm * k)
               .fill(Theme.Color.shadow)
               .scaleEffect(x: max(0.02, abs(cos(angle * .pi / 180))), y: 1)
               .offset(x: rest - t.width * 5, y: rest - t.height * 5)
               .allowsHitTesting(false)
               .accessibilityHidden(true)
       }
   }
   ```

4. **`ReelCardDetail.card`:** the overlay currently holds `faces…` with the flight
   on it. Restructure so the shadow sits under the faces and both fly together:
   ```swift
   .overlay {
       ZStack {
           if isActor {
               TableShadow(angle: reduceMotion ? 0 : (flipped ? 180 : 0))
           }
           faces
               .contentShape(Rectangle())
               .onTapGesture(perform: toggle)
               .modifier(CardTiltRotation())
       }
       .modifier(LiftFlight(progress: travels ? (out ? 1 : 0) : 1, from: slot, to: rest))
       .opacity(rest == nil ? 0 : travels ? 1 : (out ? 1 : 0))
   }
   ```
   Keep the existing comments on the flight/opacity lines. `flipped` already
   changes inside `withAnimation(Self.flip)` and inside the home flight, so
   `TableShadow.angle` animates with them for free.

## Boundaries

- Do NOT change `NeoSurface`/`neoSurface` in `Components.swift`.
- Do NOT change the grid card's shadow, `ReelFrame`, or any spring.
- No `.shadow(radius:)`, no blur, no opacity animation on the shadow.
- If plan 003 isn't in place (no `CardTilt`, no `lifted`), STOP.
- Known, out of scope: the back face's corner radius (`Theme.Radius.md` = 12pt,
  laid out at full size) is smaller than the scaled front's (8 × k ≈ 17.5pt), so
  the shadow's corners peek slightly past the back's corners. Note it in your
  report; do not change either radius.

## Verification

- **Mechanical**: `python3 scripts/swift-check.py` clean; CLAUDE.md test command green.
- **Feel check:**
  - Simulator `-uiDemoReel -uiOpenReel`: lift a card, close it. Slow animations
    (Debug → Slow Animations): on landing, the shadow under the flying card lines
    up with the grid card's shadow — no 1-px jump, no double shadow at the swap.
  - Flip: the shadow narrows to a sliver at the edge-on moment and widens again;
    the back face shows one shadow, not two.
  - Real iPhone: tip the card — the card leans, the shadow stays flat on the
    table and slides. **Sign check:** the shadow should grow on the side where the
    card tips *away* from you. If it grows on the near side instead, flip both
    signs (`+ t.width * 5`, `+ t.height * 5`) — that is the only permitted tweak.
  - Reduce Motion: shadow sits at rest, never moves or narrows.
- **Done when**: landing is seamless, the shadow never rotates with the card, and
  only one shadow is visible on either face.
