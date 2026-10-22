//
//  SeedView.swift
//  movie-quiz
//
//  The home screen. It leads with a *dealt start*, not a search box: the branded
//  lockup, then one big "Start with · <name>" button whose pill is a random
//  popular actor or movie (blue = actor, yellow = movie). Tapping it plays
//  immediately; Shuffle deals a fresh start; a quiet link drops down to the
//  search flow for players who want to pick their own. This reads as a game's
//  start screen rather than a movie-logging app.
//
//  The dealt seed is owned by the engine (`engine.dealtSeed`, refreshed on every
//  appearance and on resume). The name lives on one line, auto-sized to fit
//  (`minimumScaleFactor`, like the in-game `NodeTile`) so the button never
//  reflows — which lets Shuffle animate as one clean "deal" (old start drops out,
//  new drops in on `Theme.Motion.drop`) instead of a janky slot-machine roll.
//
//  Cold-launch intro (once ever): the lockup starts centered, its mini-chain
//  drops in, then the lockup rises to its header rest as the deal controls
//  cascade in beneath it. Gated by `introDone` (owned by `ContentView`,
//  persisted); every later launch and every "Play again" starts assembled.
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
    /// Whether the "pick your own start" search flow is showing (vs the deal).
    @State private var searching = false

    // MARK: Intro state (see `runIntro`)
    /// The mini-chain tiles have dropped in.
    @State private var chainBuilt: Bool
    /// The lockup has risen to its header rest.
    @State private var revealed: Bool
    /// How many deal controls have been revealed (0…`controlSlotCount`).
    @State private var revealedControls: Int
    /// Latches "this instance plays the intro" so it survives the view re-init
    /// that fires when `runIntro` sets the `introDone` binding (see the long note
    /// in the previous revision — a plain `let` snapped the cascade).
    @State private var playsIntro: Bool
    @State private var introTask: Task<Void, Never>?

    @State private var showSettings = false

    @AppStorage("soundEnabled") private var soundEnabled = true
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Staggered slots for the intro cascade: start button(0), hint(1),
    /// shuffle(2), search link(3).
    private static let controlSlotCount = 4

    init(engine: GameEngine, collection: CollectionStore, introDone: Binding<Bool>) {
        self.engine = engine
        self.collection = collection
        self._introDone = introDone
        let done = introDone.wrappedValue
        _playsIntro = State(initialValue: !done)
        _chainBuilt = State(initialValue: done)
        _revealed = State(initialValue: done)
        _revealedControls = State(initialValue: done ? Self.controlSlotCount : 0)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Theme.Spacing.lg) {
                // Animatable centering spacer for the intro; collapses to nothing
                // once the lockup has risen.
                Color.clear.frame(height: topInset(geo.size.height))

                titleLockup

                Group {
                    if searching {
                        searchSection
                    } else {
                        dealSection
                            .allowsHitTesting(!playsIntro || revealedControls == Self.controlSlotCount)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, searching ? Theme.Spacing.sm : Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(Theme.Motion.standard, value: searching)
        }
        .background(Theme.Color.canvas.ignoresSafeArea())
        .overlay(alignment: .topLeading) { settingsButton }
        .overlay(alignment: .topTrailing) { reelButton }
        .overlay {
            // Tap-to-skip while the intro plays (controls are inert until assembly,
            // so this never eats a real tap and is gone the instant it completes).
            if introRunning {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { skipIntro() }
                    .accessibilityLabel("Skip intro")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .sheet(isPresented: $showReel) {
            CollectionView(store: collection, bestChain: engine.bestChain)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // Deal a fresh start on every appearance (cold launch and "Play again").
        .task { await engine.prepareSeeds() }
        // Warm the haptic/audio engines HERE, on the seed screen, rather than in
        // GameView. `AVAudioEngine.start()` briefly blocks the main actor, and
        // doing it in GameView.task landed that block right on the seed->play
        // push. We wait until the entrance animation (cold-launch intro, or the
        // carousel push on a Play-again re-entry) has settled so the warm never
        // lands on an animation.
        .task(id: introRunning) { await warmFeedbackWhenIdle() }
        .onAppear {
            if introTask == nil { introTask = Task { await runIntro() } }
            #if DEBUG
            // Screenshot hook: open straight onto the Reel sheet.
            if ProcessInfo.processInfo.arguments.contains("-uiOpenReel") { showReel = true }
            #endif
        }
        .onChange(of: searching) { _, now in
            // Focus the field when the search flow opens; drop it when it closes.
            searchFocused = now
            if !now { searchTask?.cancel(); query = ""; results = [] }
        }
        .onDisappear {
            introTask?.cancel()
            searchTask?.cancel()
        }
    }

    /// The space above the title lockup. During the intro it starts tall (the
    /// lockup centered) and settles to its resting value as the controls
    /// assemble. The resting value isn't zero: a small inset lowers the title so
    /// the title + controls composition sits just above the screen's middle
    /// instead of hugging the top and leaving the bottom empty.
    private func topInset(_ height: CGFloat) -> CGFloat {
        let rest = searching ? 0 : height * 0.06
        return revealed ? rest : max(Theme.Spacing.xl, height * 0.30)
    }

    private var introRunning: Bool {
        playsIntro && revealedControls < Self.controlSlotCount
    }

    // MARK: Title lockup — mini-chain · serif wordmark · tagline
    //
    // In search mode the mini-chain and tagline fold away (the wordmark stays —
    // it's the identity) so the field + results clear the keyboard.

    private var titleLockup: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if !searching {
                chainLockup
                    .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
            }

            // Roman word + italic flourish word: the spec's heading recipe.
            Text("\(Text("Movie"))\n\(Text("Chain").font(Theme.Font.flourish(size: 46)))")
                .font(Theme.Font.display(46))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .scaleEffect(revealed ? 1 : 1.1)

            if !searching {
                Text("How long can you keep the chain alive?")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.muted)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
    }

    private var chainLockup: some View {
        HStack(spacing: 5) {
            ForEach(Array([NodeKind.actor, .movie, .actor, .movie].enumerated()), id: \.offset) { i, kind in
                RoundedRectangle(cornerRadius: 4)
                    .fill(kind.accent)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
                    .frame(width: 26, height: 15)
                    .modifier(TileBuild(shown: chainBuilt, index: i))
            }
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.Color.border, style: StrokeStyle(lineWidth: Theme.Border.width, dash: [3, 3]))
                .frame(width: 26, height: 15)
                .overlay(
                    Text("?")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Color.muted)
                )
                .modifier(TileBuild(shown: chainBuilt, index: 4))
        }
    }

    // MARK: Deal section — the dealt start, Play, Shuffle, and the search link

    // Two zones, not three: the title up top, and every control in one tight
    // group below it — start, hint, shuffle, and the search link as a quiet third
    // option rather than a footer floating on its own. The free space splits
    // 2 : 3 above and below the group, which puts the start button a little
    // below the screen's middle, where the thumb rests.
    private var dealSection: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Spacing.md)
            Spacer(minLength: 0)
            VStack(spacing: Theme.Spacing.md) {
                VStack(spacing: Theme.Spacing.sm) {
                    cascade(startButton, 0)
                    cascade(hintLine, 1)
                }
                cascade(shuffleButton, 2)
                cascade(searchLink, 3)
                    .padding(.top, Theme.Spacing.xs)
            }
            Spacer(minLength: Theme.Spacing.md)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Play + seed as one button. The chrome ("START WITH") and the button frame
    // stay fixed; only the inner seed content deals in/out, so the button never
    // jumps. Disabled until the first deal lands (pool still loading).
    private var startButton: some View {
        Button { play() } label: {
            VStack(spacing: Theme.Spacing.sm) {
                Text("Start with")
                    .metaLabel(.white.opacity(0.85))
                seedContent
            }
        }
        .buttonStyle(StartButtonStyle())
        .disabled(engine.dealtSeed == nil)
    }

    private var seedContent: some View {
        ZStack {
            if let seed = engine.dealtSeed {
                HStack(spacing: Theme.Spacing.sm) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(seed.accent)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
                        .frame(width: 14, height: 14)
                    Text(seed.matchText)                 // bare name/title, no year
                        // Fixed size (not a text style): the button's height is
                        // locked so the deal transition never reflows.
                        .font(Theme.Font.display(26))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)          // shrink to fit, never clip
                }
                .id(seed.id)
                .transition(reduceMotion ? .opacity : .dealDrop)
            } else {
                Text("Dealing…")
                    .font(Theme.Font.flourish(size: 20))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(height: 40)                                // fixed one-line height
        .animation(reduceMotion ? nil : Theme.Motion.drop, value: engine.dealtSeed)
    }

    private var hintLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
            Text(engine.dealtSeed?.nextKind.prompt ?? " ")
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.muted)
        .contentTransition(.opacity)
        .animation(reduceMotion ? nil : Theme.Motion.standard, value: engine.dealtSeed)
    }

    private var shuffleButton: some View {
        Button {
            Haptics.selection()
            engine.shuffleSeed()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "shuffle")
                Text("Shuffle")
            }
        }
        .buttonStyle(.ghost)
        .disabled(engine.dealtSeed == nil)
    }

    private var searchLink: some View {
        Button {
            withAnimation(Theme.Motion.standard) { searching = true }
        } label: {
            Text("or search for your own start")
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(Theme.Color.muted)
                .underline(true, pattern: .solid)
        }
        .buttonStyle(.plain)
    }

    private func play() {
        guard let seed = engine.dealtSeed else { return }
        searchTask?.cancel()
        Task { await engine.startGame(with: seed) }
    }

    // MARK: Reel — a single corner button (also the route to the TMDB attribution)

    // Always reachable (not gated on `collection.total > 0`): the Reel sheet holds
    // the required TMDB attribution, so a first-run player — who is already being
    // served TMDB-powered dealt seeds — must be able to open it before logging any
    // chain. The count only appears once there's something to count, so an empty
    // Reel reads as a quiet "open your collection / about" affordance, keeping the
    // home play-first while the attribution stays one tap away.
    // A quiet gear that mirrors the Reel pill on the opposite corner — the route
    // to the (new) settings sheet. Hidden during search and the intro, exactly
    // like the Reel pill, so the home stays clean.
    @ViewBuilder private var settingsButton: some View {
        if !searching, !introRunning {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.ink)
                    .padding(.horizontal, Theme.Spacing.sm + 2)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .neoSurface(radius: Theme.Radius.pill, shadow: Theme.Shadow.small)
            }
            .buttonStyle(.plain)
            .padding(.leading, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.xs)
            .transition(.opacity)
            .accessibilityLabel("Settings")
        }
    }

    @ViewBuilder private var reelButton: some View {
        if !searching, !introRunning {
            Button { showReel = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "film.stack")
                    if collection.total > 0 {
                        Text("\(collection.total)")
                            .font(Theme.Font.numeral(.subheadline))
                            .monospacedDigit()
                    }
                }
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(Theme.Color.ink)
                .padding(.horizontal, Theme.Spacing.sm + 2)
                .padding(.vertical, Theme.Spacing.xs + 2)
                .neoSurface(radius: Theme.Radius.pill, shadow: Theme.Shadow.small)
            }
            .buttonStyle(.plain)
            .padding(.trailing, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.xs)
            .transition(.opacity)
            .accessibilityLabel(collection.total > 0 ? "Your Reel, \(collection.total) logged" : "Your Reel")
        }
    }

    // MARK: Search section — the demoted "pick your own start" flow

    private var searchSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Button {
                    withAnimation(Theme.Motion.standard) { searching = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Deal a start")
                    }
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.muted)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            segment
            searchField
            resultsSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Start-kind segment (actor / movie)

    private var segment: some View {
        HStack(spacing: 4) {
            segmentButton(.actor)
            segmentButton(.movie)
        }
        .padding(4)
        .neoSurface(radius: Theme.Radius.md, shadow: Theme.Shadow.small)
    }

    private func segmentButton(_ kind: NodeKind) -> some View {
        Button {
            guard engine.seedKind != kind else { return }
            Haptics.selection()
            engine.seedKind = kind
            runSearch()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.symbol)
                    .font(Theme.Font.small.weight(.bold))
                Text(kind == .actor ? "Actor" : "Movie")
                    .font(Theme.Font.button)
                    .textCase(.uppercase)
                    .tracking(Theme.Font.buttonTracking)
            }
        }
        .buttonStyle(SegmentButtonStyle(kind: kind, selected: engine.seedKind == kind))
    }

    // MARK: Search field (in-app styled, not a system search bar)

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Color.muted)
            TextField(engine.seedKind == .actor ? "Search actors" : "Search movies", text: $query)
                .font(Theme.Font.body)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Color.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: 44)
        .neoSurface(radius: Theme.Radius.md, shadow: Theme.Shadow.small)
        .onChange(of: query) { runSearch() }
    }

    // MARK: Results — warm-tile rows with a category dot

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
            NodeName(node: node)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(Theme.Font.small.weight(.bold))
                .foregroundStyle(Theme.Color.muted)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md - 2)
        .neoSurface(radius: Theme.Radius.md, shadow: Theme.Shadow.small)
        .padding(.trailing, Theme.Shadow.small)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            SplitHeading(roman: query.isEmpty ? "Pick your" : "No",
                         flourish: query.isEmpty ? "start" : "matches")
            Text(query.isEmpty
                 ? "Search an \(engine.seedKind == .actor ? "actor" : "movie") to begin your chain."
                 : "Try a different spelling.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, Theme.Spacing.lg)
    }

    // MARK: Search plumbing

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
        searchTask?.cancel()
        Task { await engine.startGame(with: node) }
    }

    // MARK: Intro sequence

    private func cascade<V: View>(_ view: V, _ index: Int) -> some View {
        view.modifier(ControlReveal(visible: revealedControls > index, enabled: playsIntro))
    }

    private func runIntro() async {
        if introDone || reduceMotion {
            chainBuilt = true
            revealed = true
            revealedControls = Self.controlSlotCount
            introDone = true
            return
        }
        chainBuilt = true                                        // 1. mini-chain drops in
        try? await Task.sleep(for: .milliseconds(950))
        if Task.isCancelled { return }
        withAnimation(Theme.Motion.intro) { revealed = true }     // 2. lockup rises
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }
        for slot in 0..<Self.controlSlotCount {                   // 3. controls deal in
            withAnimation(Theme.Motion.cascade) { revealedControls = slot + 1 }
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
        introDone = true                                          // (re-inits the view — last)
    }

    /// Warm haptics + audio once the screen is idle. Re-run by `.task(id:)` when
    /// `introRunning` changes (false after the intro completes *or* is skipped, and
    /// immediately on a re-entry), then waits out the entrance/push settle before
    /// paying the briefly-blocking `AVAudioEngine.start()` — keeping that cost off
    /// every animation, especially the seed->play transition (GameView no longer
    /// warms).
    private func warmFeedbackWhenIdle() async {
        guard !introRunning else { return }
        try? await Task.sleep(for: .milliseconds(700))   // clear the settle / carousel push
        guard !Task.isCancelled else { return }
        Haptics.prepare()
        if soundEnabled { SoundPlayer.shared.warm() }
    }

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
}

// MARK: - Start button style (the coral "Start with …" card)

/// The home's primary action: a coral card carrying the "START WITH" label and
/// the dealt seed. Coral because it is this screen's call-to-action, exactly
/// like "Play again" on game over (an ink fill also hid its ink shadow, which
/// made the card read as shifted). Its own style rather than
/// `PrimaryButtonStyle` because it hosts multi-line content and a taller radius.
private struct StartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md + 2)
            .padding(.horizontal, Theme.Spacing.md)
            // The screen's one loud surface: ink fill, hard shadow, and the
            // neobrutalist press (shadow collapses, card shifts into the page).
            .neoSurface(radius: Theme.Radius.card + 4,
                        fill: configuration.isPressed ? Theme.Color.primaryPressed : Theme.Color.primary,
                        pressed: configuration.isPressed)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Deal transition
//
// The single "deal": the old start drops out downward while the new one drops in
// from above — the same falling motion a chain tile lands on in-game. Because the
// name is always one line (auto-sized), the button height is fixed, so this reads
// as a clean replacement with no reflow. Reduce Motion uses a plain cross-fade.

private struct DealShift: ViewModifier {
    var y: CGFloat
    var opacity: Double
    func body(content: Content) -> some View {
        content.offset(y: y).opacity(opacity)
    }
}

private extension AnyTransition {
    static var dealDrop: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: DealShift(y: -13, opacity: 0), identity: DealShift(y: 0, opacity: 1)),
            removal: .modifier(active: DealShift(y: 12, opacity: 0), identity: DealShift(y: 0, opacity: 1))
        )
    }
}

// MARK: - Segment toggle button style

/// One side of the actor/movie toggle (search flow). A `ButtonStyle` so the whole
/// padded width is tappable and the press squish reads; active side fills solid
/// with its category accent.
private struct SegmentButtonStyle: ButtonStyle {
    let kind: NodeKind
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? kind.onAccent : Theme.Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(selected ? kind.accent : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .strokeBorder(selected ? Theme.Color.border : .clear, lineWidth: Theme.Border.width))
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.Motion.standard, value: configuration.isPressed)
            .animation(Theme.Motion.emphasized, value: selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Control cascade reveal

/// Rises + grows + fades one control into place once its slot is dealt in (intro
/// only). Shown at once on a "Play again" re-entry (`enabled == false`) and under
/// Reduce Motion.
private struct ControlReveal: ViewModifier {
    let visible: Bool
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = visible || !enabled || reduceMotion
        return content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.94, anchor: .bottom)
            .offset(y: shown ? 0 : 26)
            .disabled(!shown)
            .accessibilityHidden(!shown)
    }
}

// MARK: - Mini-chain tile build

/// Drops one lockup tile in — scaling up from just above its slot — delayed by
/// its position, so the mini-chain assembles left-to-right like the in-game
/// stack landing. No-op under Reduce Motion.
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
