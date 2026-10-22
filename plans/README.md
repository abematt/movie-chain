# Animation plans

Written by the `improve-animations` audit of the Reel's lifted actor card (commit
`8f02df1`, 2026-10-22), before the gyro tilt / glare / parallax / drag work was
built. Each plan is self-contained; run them in order.

| # | Plan | Severity | Depends on | Status |
|---|---|---|---|---|
| 001 | [Run the tilt on the display clock](001-tilt-on-the-display-clock.md) | MEDIUM | — | DONE (120Hz key reverted — see note) |
| 002 | [Move the holo foil by transform](002-foil-moves-by-transform.md) | HIGH | — | DONE |
| 003 | [Lifted card tilts from leaf views](003-lifted-card-tilts-from-a-leaf-layer.md) | HIGH | 001, 002 | DONE |
| 004 | [Table shadow for the lifted card](004-table-shadow-for-the-lifted-card.md) | HIGH | 003 | DONE |
| 005 | [Drag to tilt, spring back with the flick](005-drag-to-tilt-fallback.md) | MEDIUM | 001, 003 | DONE |

## Order

`001 → 002 → 003 → 004 → 005`. 001 and 002 are independent of each other and
improve the existing stickers on their own; 003 is the feature; 004 and 005
build on it.

## The rules these plans encode

- **Nothing that changes per frame reaches a big view body.** Tilt is read only
  in leaf views (`ReelFoil`, `ReelParallax`, `ReelGlare`, `CardTiltRotation`,
  `TableShadow`); the card receives a stable environment *reference*, never the value.
- **Per-frame motion moves pixels, it doesn't redraw them**: `offset`,
  `rotation3DEffect`, `scaleEffect`, `opacity`, `hueRotation` — not gradient
  geometry, not `.shadow(radius:)`, not layout.
- **One clock.** Gyro smoothing, intensity ramps and the drag release all run on
  `DisplayLink` with time-based maths and hand-sampled `Spring`s, so per-frame
  gyro writes can never cancel a SwiftUI animation.
- **The card flies flat.** Tilt intensity is 0 at take-off and landing, so
  `LiftFlight` still lands pixel-for-pixel on the grid slot.
- **No `drawingGroup()` up front.** Only add it if an Instruments recording on a
  real device shows dropped frames.
- **Verify on a real iPhone.** The simulator has no gyro and hides frame-budget problems.

## Build notes (2026-10-22, branch `feature_reel-tilt`)

- **001**: `INFOPLIST_KEY_CADisableMinimumFrameDurationOnPhone` is not a key Xcode's
  generated Info.plist recognises — it never reached the built plist, so it was
  reverted. The tilt runs at 60Hz on ProMotion until a real Info.plist carries
  `CADisableMinimumFrameDurationOnPhone = YES`.
- **002**: the plan's "3× oversized gradient" would have spread the palette three
  times wider. Built instead with each layer widened by exactly its travel and the
  original gradient endpoints mapped into it, so the foil is identical at rest.
- **003–005** were built together; `-uiLiftFirst` (DEBUG) was added to lift the first
  card for checking. Device feel-checks (gyro, shadow/flick signs, frame rate) are
  still to do.
