# 001 — Run the tilt on the display clock, not the sensor clock

- **Status**: DONE
- **Commit**: 8f02df1
- **Severity**: MEDIUM (foundation — plans 003–005 depend on it)
- **Category**: Performance
- **Estimated scope**: 2 Swift files + optional 2 lines in `project.pbxproj`; ~120 lines

## Problem

`TiltMotion` smooths the gyro **once per sensor sample**, so its feel is welded to
the 30Hz update rate. Raising the rate (needed once tilt moves geometry, not just
foil colour) would silently double the baseline drift speed and change the
smoothing. And a 30Hz signal applied to geometry on a 120Hz screen visibly steps.

```swift
// movie-quiz/HoloSticker.swift:271-310 — current
manager.deviceMotionUpdateInterval = 1.0 / 30
manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
    guard let gravity = motion?.gravity else { return }
    let x = gravity.x, y = gravity.y
    MainActor.assumeIsolated { self?.update(x: x, y: y) }
}
...
private func update(x: Double, y: Double) {
    let raw = CGSize(width: x, height: y)
    var base = baseline ?? raw
    base.width += (raw.width - base.width) * 0.02
    base.height += (raw.height - base.height) * 0.02
    baseline = base
    let gain: CGFloat = 3
    let target = CGSize(width: clamp((raw.width - base.width) * gain),
                        height: clamp((raw.height - base.height) * gain))
    tilt = CGSize(width: tilt.width + (target.width - tilt.width) * 0.3,
                  height: tilt.height + (target.height - tilt.height) * 0.3)
}
```

Second issue: the new-best `HoloSticker` in `GameOverView` stays mounted under the
Reel sheet (`movie-quiz/GameOverView.swift:74` presents the sheet,
`:128` draws the sticker). A `.sheet` does not fire `onDisappear` on the view
beneath it, so the sticker keeps the gyro running and re-renders unseen for as long
as the Reel is open.

## Target

- The sensor callback only **stores** the latest gravity reading (unobserved).
- A `CADisplayLink` (running only while `users > 0`) advances smoothing per display
  frame using elapsed time, and writes the observed `tilt` once per frame.
- Time constants reproduce today's feel exactly:
  - smoothing τ = **0.093 s** (= 0.3 per sample at 30Hz)
  - baseline drift τ = **1.65 s** (= 0.02 per sample at 30Hz)
  - per frame: `alpha = 1 - exp(-dt / tau)`
- Sensor rate **60Hz** (`1.0 / 60`). Gain 3 and the ±1 clamp unchanged.
- Display link asks for up to 120Hz:
  `preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)`.
- `HoloSticker` gains `var active = true`; when false it draws the still sticker
  (which removes the live branch, firing its `onDisappear` → `stop()`).
  `GameOverView` passes `active: !showReel`.

## Repo conventions to follow

- Main-actor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); no
  `DispatchQueue.main`, no `Task.detached`, no `print(` — `scripts/swift-check.py`
  runs on every edit and rejects them.
- Comment style: short `///` doc comments that say *why*, as in `TiltMotion` today.
- Spring/clock precedent: `Handoff.swift:177` samples `Theme.Motion.handoffSpring`
  on its own clock — the same "own clock, no SwiftUI animation" approach.

## Steps

1. **New file `movie-quiz/DisplayLink.swift`:**
   ```swift
   import QuartzCore

   /// A display-synced frame callback, for motion SwiftUI animations can't drive
   /// (a live sensor, a spring sampled by hand). Runs only between `start` and
   /// `stop`; a running link retains this object, so always pair them.
   final class DisplayLink: NSObject {
       private var link: CADisplayLink?
       private var last: CFTimeInterval?
       private let onFrame: (_ dt: Double) -> Void

       init(onFrame: @escaping (_ dt: Double) -> Void) { self.onFrame = onFrame }

       var isRunning: Bool { link != nil }

       func start() {
           guard link == nil else { return }
           let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
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
   ```
   If the compiler rejects the `@objc` selector under main-actor isolation, STOP
   and report the exact diagnostic — do not add `nonisolated`/`@preconcurrency`
   by guesswork.

2. **`movie-quiz/HoloSticker.swift`, `TiltMotion`:** replace the stored state and
   `start`/`stop`/`update` with:
   ```swift
   @ObservationIgnored private let manager = CMMotionManager()
   @ObservationIgnored private var users = 0
   /// The latest gravity reading. Unobserved: only the frame tick reads it.
   @ObservationIgnored private var raw: CGSize?
   @ObservationIgnored private var baseline: CGSize?
   @ObservationIgnored private lazy var frames = DisplayLink { [weak self] dt in self?.advance(dt) }

   /// Smoothing so sensor jitter doesn't shimmer the foil.
   private static let smoothing = 0.093
   /// How long a held angle takes to become "level".
   private static let drift = 1.65
   private static let gain: CGFloat = 3
   ```
   `start()`: keep the `users` counting; set `deviceMotionUpdateInterval = 1.0 / 60`;
   the handler becomes `MainActor.assumeIsolated { self?.raw = CGSize(width: x, height: y) }`;
   then `frames.start()`.
   `stop()`: when `users` hits 0 — `manager.stopDeviceMotionUpdates()`,
   `frames.stop()`, `raw = nil`, `baseline = nil`, `tilt = .zero`.
   New:
   ```swift
   /// One display frame: drift the baseline toward the held angle and ease the
   /// tilt toward the reading, by elapsed time — so the feel doesn't change with
   /// the sensor or screen rate.
   private func advance(_ dt: Double) {
       guard let raw else { return }
       var base = baseline ?? raw
       let d = CGFloat(1 - exp(-dt / Self.drift))
       base.width += (raw.width - base.width) * d
       base.height += (raw.height - base.height) * d
       baseline = base
       let target = CGSize(width: clamp((raw.width - base.width) * Self.gain),
                           height: clamp((raw.height - base.height) * Self.gain))
       let s = CGFloat(1 - exp(-dt / Self.smoothing))
       tilt = CGSize(width: tilt.width + (target.width - tilt.width) * s,
                     height: tilt.height + (target.height - tilt.height) * s)
   }
   ```
   Delete the old `update(x:y:)`. Update the `TiltMotion` doc comment to say the
   tilt advances per display frame.

3. **`HoloSticker`:** add `var active = true` (doc: "False while covered — a sheet
   over it — so a sticker nobody can see doesn't keep the gyro running.") and
   change the still-branch condition to
   `if reduceMotion || !active || !TiltMotion.shared.isAvailable`.

4. **`movie-quiz/GameOverView.swift:128`:** pass `active: !showReel` to the
   `HoloSticker(...)` call (argument order: after `shadow:`, before `wearSeed:`,
   matching the property order).

5. **120Hz on ProMotion iPhones (decision: do it — it's one key and only lifts a
   cap).** In `movie-quiz.xcodeproj/project.pbxproj`, directly under each of the
   two `INFOPLIST_KEY_CFBundleDisplayName = Unspool;` lines (app target Debug and
   Release, lines ~336 and ~382), add:
   ```
   				INFOPLIST_KEY_CADisableMinimumFrameDurationOnPhone = YES;
   ```
   After building, confirm it landed:
   `plutil -p <DerivedData>/…/movie-quiz.app/Info.plist | grep CADisable`.
   If it is absent (Xcode didn't recognise the generated key), revert this step
   and report — do not hand-create an Info.plist.

## Boundaries

- Do NOT change the gain (3), the clamp, or what `tilt` means (−1…1 each axis).
- Do NOT touch `HoloFoil`, `ReelCards.swift`, or `CollectionView.swift` — later plans.
- Do NOT move sensor delivery off the main queue; only do that if a device
  recording later shows the main thread is the bottleneck.
- If the code doesn't match the excerpts above, STOP and report.

## Verification

- **Mechanical**: `python3 scripts/swift-check.py` clean;
  `xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16' test` green
  (warnings are errors in this project).
- **Feel check (real iPhone — the simulator has no gyro):**
  - Win a run with a new best; tilt the phone — the sticker's foil shifts as
    smoothly as before (same lag, same "settles level after a couple of seconds").
  - Open the Reel from game over; in Instruments → Time Profiler, `advance` and
    the sticker's body are **not** sampled while the sheet is up.
  - Close the sheet — the sticker resumes catching light.
  - On a ProMotion iPhone, Instruments → Core Animation FPS reads ~120 while tilting.
- **Done when**: tilt feel is unchanged on device, the link stops when no sticker
  or card is showing (no `advance` samples on the play screen), and the covered
  sticker is idle.
