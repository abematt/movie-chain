//
//  SeedView.swift
//  movie-quiz
//
//  The home screen — a branded landing that doubles as the seed picker. This is
//  the only screen that uses global search (there is no bounded candidate set
//  until play begins). Styled as a puzzle-page landing (serif wordmark, warm-tile
//  surfaces, the two category accents) on the shared design system, rather than a
//  stock navigation/list/`.searchable` screen, which reads as "iOS Settings".
//
//  Layout: a "hero + live search" home. The wordmark, tagline, and your
//  best/Reel stats own the resting screen; a slim actor/movie segment and a
//  tap-to-focus search field sit beneath, and results reveal inline as you type
//  (no push, no new screen) — so the fastest path to play stays: tap the field →
//  type → tap a result.
//
//  Keyboard-aware collapse: the moment the field is focused (or any text is
//  typed) the hero folds — mini-chain, tagline, and stat chips fade out and the
//  top padding tightens — so the field and its results rise clear of the
//  keyboard. The results list is the flexible region, so it absorbs the reduced
//  height and everything stays on screen. Clearing the field re-expands the hero.
//
//  Cold-launch intro: on the very first launch the title lockup starts centered,
//  its mini-chain drops in tile-by-tile (echoing the in-game Tetris landing),
//  then the lockup rises to its header rest as the controls assemble beneath it.
//  Runs once ever — `introDone` (owned by `ContentView`, persisted) is already
//  true on every later launch and every "Play again" re-entry, so the screen
//  starts assembled and the carousel push never flashes a centered logo. Reduce
//  Motion skips it all.
//

import SwiftUI

struct SeedView: View {
    var engine: GameEngine
    var collection: CollectionStore
    @Binding var introDone: Bool

    @State private var query = ""
    @State private var results: [ChainNode] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var showReel = false
    /// The mini-chain tiles have dropped in.
    @State private var chainBuilt: Bool
    /// The lockup has risen to its header rest.
    @State private var revealed: Bool
    /// How many controls have been revealed so far (0…`controlSlotCount`). Driven
    /// up one at a time by `runIntro`, each step inside its own `withAnimation`
    /// spaced by a real delay, so each control springs in on its own transaction.
    @State private var revealedControls: Int
    /// Latches "this instance plays the intro" in `@State` so it survives the view
    /// re-init that fires when `runIntro` finally sets the `introDone` binding. A
    /// plain `let` derived from `introDone` flips to false on that re-init *mid
    /// cascade* — which disables the reveal animation and snaps every remaining
    /// control in at once (the exact bug that made the controls pop while the
    /// mini-chain, which finishes before `introDone` is touched, animated fine).
    @State private var playsIntro: Bool
    /// The running intro sequence, held so a tap can cancel it (skip-to-assembled).
    @State private var introTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Number of staggered control slots — badges(0), segment(1), search(2),
    /// results(3). See `controls`.
    private static let controlSlotCount = 4

    init(engine: GameEngine, collection: CollectionStore, introDone: Binding<Bool>) {
        self.engine = engine
        self.collection = collection
        self._introDone = introDone
        // If the intro already played this launch, start fully assembled so a
        // "Play again" re-entry settles instantly under the carousel push.
        let done = introDone.wrappedValue
        _playsIntro = State(initialValue: !done)
        _chainBuilt = State(initialValue: done)
        _revealed = State(initialValue: done)
        _revealedControls = State(initialValue: done ? Self.controlSlotCount : 0)
    }

    /// The hero folds (mini-chain / tagline / stat chips out, padding tight) once
    /// the player engages the search — either the field is focused or they've
    /// typed something. Keying it to the query too keeps the hero compact after an
    /// interactive scroll-to-dismiss (keyboard gone but results still on screen),
    /// so the list doesn't jump when focus is lost mid-browse.
    private var heroCollapsed: Bool {
        searchFocused || !query.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Theme.Spacing.lg) {
                // Animatable centering spacer: pushes the lockup toward the middle
                // during the intro, collapses to nothing once assembled.
                Color.clear.frame(height: topInset(geo.size.height))

                titleLockup

                // Always mounted (like the mini-chain tiles) so each control's
                // reveal animates on a view that's been on screen since launch;
                // hidden + inert until its slot is dealt in. Gating this behind an
                // `if` makes SwiftUI snap them in instead.
                controls
                    .allowsHitTesting(!playsIntro || revealedControls == Self.controlSlotCount)
            }
            .padding(.horizontal)
            .padding(.top, heroCollapsed ? Theme.Spacing.sm : Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(Theme.Motion.standard, value: heroCollapsed)
        }
        .background(Theme.Color.canvas.ignoresSafeArea())
        // Tap-to-skip: while the intro is still playing, a tap anywhere collapses
        // it to the assembled screen. The controls are inert (`allowsHitTesting`)
        // during the intro, so this catcher owns every touch until assembly — and
        // it's gone the instant assembly completes, so it never eats a real tap.
        .overlay {
            if introRunning {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { skipIntro() }
                    .accessibilityLabel("Skip intro")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .sheet(isPresented: $showReel) {
            CollectionView(store: collection)
        }
        .onAppear {
            if introTask == nil { introTask = Task { await runIntro() } }
        }
        .onDisappear {
            introTask?.cancel()
            searchTask?.cancel()   // a pending debounced search must not outlive the screen
        }
    }

    private func topInset(_ height: CGFloat) -> CGFloat {
        revealed ? 0 : max(Theme.Spacing.xl, height * 0.30)
    }

    /// True while the scripted intro is mid-flight — drives the skip-catcher.
    /// Once the last control is dealt in, assembly is complete and this is false.
    private var introRunning: Bool {
        playsIntro && revealedControls < Self.controlSlotCount
    }

    // MARK: Intro sequence

    private func runIntro() async {
        // Already played (ever), or motion is reduced: show it assembled.
        if introDone || reduceMotion {
            chainBuilt = true
            revealed = true
            revealedControls = Self.controlSlotCount
            introDone = true
            return
        }
        chainBuilt = true                                        // 1. mini-chain drops in
        try? await Task.sleep(for: .milliseconds(950))            //    build + hold
        if Task.isCancelled { return }                            //    (tapped to skip)
        withAnimation(Theme.Motion.intro) { revealed = true }     // 2. lockup rises
        try? await Task.sleep(for: .milliseconds(500))            //    let the rise settle
        if Task.isCancelled { return }
        for slot in 0..<Self.controlSlotCount {                   // 3. controls deal in one-by-one
            withAnimation(Theme.Motion.cascade) { revealedControls = slot + 1 }
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
        introDone = true                                          //    (re-inits the view — must be last)
    }

    /// Collapse the running intro straight to the assembled screen. Cancels the
    /// sequence (so its remaining steps bail at the next `Task.isCancelled` check)
    /// and settles every stage at once on a single quick spring.
    private func skipIntro() {
        guard playsIntro, !introDone else { return }
        introTask?.cancel()
        withAnimation(Theme.Motion.cascade) {
            chainBuilt = true
            revealed = true
            revealedControls = Self.controlSlotCount
        }
        introDone = true
    }

    // MARK: Title lockup — mini-chain · serif wordmark · tagline
    //
    // Collapses on `heroCollapsed`: the mini-chain and tagline fold away (the
    // wordmark stays — it's the identity) so the search + results clear the
    // keyboard. Both are always mounted during the intro (`heroCollapsed` is
    // false throughout it), so their intro entrance still animates via `TileBuild`
    // and the lockup rise; the collapse fade only fires later, on focus/typing.

    private var titleLockup: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if !heroCollapsed {
                chainLockup
                    .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
            }

            Text("Movie\nChain")
                .font(.system(size: 46, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .scaleEffect(revealed ? 1 : 1.1)

            if !heroCollapsed {
                Text("How long can you keep the chain alive?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Chain lockup — an ambient mini-chain that telegraphs the game

    private var chainLockup: some View {
        HStack(spacing: 5) {
            ForEach(Array([NodeKind.actor, .movie, .actor, .movie].enumerated()), id: \.offset) { i, kind in
                RoundedRectangle(cornerRadius: 4)
                    .fill(kind.accent)
                    .frame(width: 26, height: 15)
                    .modifier(TileBuild(shown: chainBuilt, index: i))
            }
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.Color.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                .frame(width: 26, height: 15)
                .overlay(
                    Text("?")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                )
                .modifier(TileBuild(shown: chainBuilt, index: 4))
        }
    }

    // MARK: Controls — assembled beneath the lockup on reveal

    // The controls deal in one at a time *after* the lockup has risen — each
    // rises + grows into place on the smooth `cascade` spring (a gentle
    // overshoot). The stagger is real time, not a baked-in `.delay`: `runIntro`
    // bumps `revealedControls` one slot at a time inside its own `withAnimation`,
    // spaced by a 100ms sleep, so each control springs in on its own transaction
    // and reads as a distinct beat.
    private func cascade<V: View>(_ view: V, _ index: Int) -> some View {
        view.modifier(ControlReveal(visible: revealedControls > index, enabled: playsIntro))
    }

    @ViewBuilder private var controls: some View {
        // The stat chips are part of the hero, so they fold with it. Mounted
        // throughout the intro (`heroCollapsed` stays false there) so slot 0 still
        // cascades in; removed only later when the hero collapses.
        if !heroCollapsed {
            cascade(badges, 0)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        cascade(segment, 1)
        cascade(searchField, 2)
        cascade(resultsSection, 3)
    }

    // MARK: Stat chips (personal best · Your Reel)

    private var badges: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if engine.bestChain > 0 {
                Text("Your best · \(engine.bestChain) links")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .overlay(Capsule().strokeBorder(Theme.Color.hairline, lineWidth: 1))
            }
            if collection.total > 0 {
                Button { showReel = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "film.stack")
                        Text("Your Reel · \(collection.total)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .overlay(Capsule().strokeBorder(Theme.Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Start choice — an actor/movie toggle

    // The two big category tiles from the old landing shrink to a compact
    // segmented toggle: it names the choice and carries the category accents
    // without eating the vertical room the hero + results now want. The active
    // side fills solid with its category color (blue = actor, purple = movie) so
    // the on/off state reads at a glance. Switching side re-points the search (and
    // re-runs it if there's a query) but does not force-focus, so it never yanks
    // the keyboard up on its own.
    private var segment: some View {
        HStack(spacing: 4) {
            segmentButton(.actor)
            segmentButton(.movie)
        }
        .padding(4)
        .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.Color.hairline, lineWidth: 1)
        )
    }

    private func segmentButton(_ kind: NodeKind) -> some View {
        Button {
            // Only act on a real change: keeps the detent haptic honest (no tick
            // for re-tapping the side you're already on) and avoids a redundant
            // search kick.
            guard engine.seedKind != kind else { return }
            Haptics.selection()
            engine.seedKind = kind
            runSearch()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.symbol)
                    .font(.footnote.weight(.bold))
                Text(kind == .actor ? "Actor" : "Movie")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(SegmentButtonStyle(kind: kind, selected: engine.seedKind == kind))
    }

    // MARK: Search field (in-app styled, not a system search bar)

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(engine.seedKind == .actor ? "Search actors" : "Search movies", text: $query)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 4)
        .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onChange(of: query) { runSearch() }
    }

    // MARK: Results — warm-tile rows with a category dot
    //
    // The flexible region: it fills the space between the search field and the
    // bottom safe area, so when the keyboard raises that inset the list shrinks to
    // fit and the field + first rows stay clear of the keys.

    @ViewBuilder private var resultsSection: some View {
        if results.isEmpty {
            emptyState
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(results) { node in
                    Button { start(with: node) } label: { resultRow(node) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultRow(_ node: ChainNode) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            NodeDot(kind: node.kind, size: 11)
            Text(node.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md - 2)
        .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(query.isEmpty ? "Pick your start" : "No matches")
                .font(.headline)
            Text(query.isEmpty
                 ? "Search an \(engine.seedKind == .actor ? "actor" : "movie") to begin your chain."
                 : "Try a different spelling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, Theme.Spacing.lg)
    }

    // MARK: Search

    private func runSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250)) // debounce
            if Task.isCancelled { return }
            let found = await engine.search(q)
            if Task.isCancelled { return }
            results = found
        }
    }

    private func start(with node: ChainNode) {
        searchTask?.cancel()   // don't let a still-pending debounced search resume into the round
        Task { await engine.startGame(with: node) }
    }
}

// MARK: - Segment toggle button style

/// One side of the actor/movie toggle. A `ButtonStyle` (not a `.plain` button)
/// for two reasons: it exposes `configuration.isPressed` for the press-down
/// squish, and its `contentShape` makes the *entire* padded width tappable —
/// `.plain` only hit-tests the opaque label glyphs, which is why the old toggle
/// dropped touches that landed on the empty padding. The active side fills solid
/// with its category accent (near-black glyphs on the pastel); the inactive side
/// is a quiet, tinted glyph on the track. Both transitions animate.
private struct SegmentButtonStyle: ButtonStyle {
    let kind: NodeKind
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Theme.Color.onAccent : kind.accent.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(selected ? kind.accent : Color.clear)
                    .shadow(color: selected ? .black.opacity(0.14) : .clear, radius: 3, y: 1)
            }
            // The whole padded frame is the hit target, so a touch anywhere on the
            // half registers — no more dead padding.
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.Motion.standard, value: configuration.isPressed)
            .animation(Theme.Motion.emphasized, value: selected)
            // Expose on/off to VoiceOver like a real segmented control, so the
            // active side is announced "selected" rather than just looking filled.
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Control cascade reveal

/// Rises + grows + fades one control into place once its slot is dealt in. The
/// animation itself lives in `runIntro`'s `withAnimation` loop, not here — this
/// just declares the hidden vs shown geometry. Shown at once (no stagger) on a
/// "Play again" re-entry (`enabled == false`) and under Reduce Motion.
private struct ControlReveal: ViewModifier {
    /// Whether this control's slot has been dealt in yet.
    let visible: Bool
    /// False on a "Play again" re-entry — the controls arrive solid, no stagger.
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // No implicit `.animation` here — the spring comes from the `withAnimation`
        // in `runIntro` that flips this slot on, so the reveal and its animation
        // ride the same transaction (an implicit one would be silently dropped
        // when `introDone` re-inits the view mid-cascade).
        let shown = visible || !enabled || reduceMotion
        return content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.94, anchor: .bottom)
            .offset(y: shown ? 0 : 26)
            // Keep the reveal gate honest across every input path: a slot that's
            // visually hidden is also removed from the accessibility tree and
            // disabled, so VoiceOver/Switch Control can't focus or activate a
            // control that isn't on screen yet during the cold-launch intro.
            .disabled(!shown)
            .accessibilityHidden(!shown)
    }
}

// MARK: - Mini-chain tile build

/// Drops one lockup tile in — scaling up from just above its slot — with a delay
/// keyed to its position, so the mini-chain assembles left-to-right like the
/// in-game stack landing. No-op under Reduce Motion.
private struct TileBuild: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.5, anchor: .bottom)
            .offset(y: shown ? 0 : -12)
            .animation(reduceMotion ? nil : Theme.Motion.drop.delay(Double(index) * 0.10), value: shown)
    }
}

#Preview {
    SeedView(engine: GameEngine(), collection: CollectionStore(fileURL: nil), introDone: .constant(true))
}
