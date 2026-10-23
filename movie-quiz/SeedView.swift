//
//  SeedView.swift
//  movie-quiz
//
//  The home screen, written as the first turn: "Chris Hemsworth was in ___".
//  Under the Unspool wordmark (with the Reel and settings pills) sits the dealt
//  start as the opening of a sentence — avatar and kind chip, the name in big
//  serif, "was in" (or "starred", for a movie) — and a blank. The blank is the
//  start button: tapping it hands off to the play screen in place (see
//  `Handoff.swift`), the sentence flying into the deck and the blank into the
//  answer dock as the keyboard comes up. "Deal again" deals a fresh start;
//  "Pick your own" drops down to the search flow. The best run sits centred at
//  the foot of the screen. There's no instruction: the sentence is the rule, and the blank
//  nudges once, ever, to show it's the way in.
//
//  The dealt seed is owned by the engine (`engine.dealtSeed`, refreshed on every
//  appearance and on resume). Once a start has sat on screen for a moment, the
//  engine prefetches its candidates, so its first turn is ready the moment the
//  keyboard is up.
//
//  Cold-launch intro (once ever): the wordmark appears centered and large, rises
//  to its header rest, and the rest of the screen cascades in beneath it. Gated
//  by `introDone` (owned by `ContentView`, persisted); every later launch and
//  every "Play again" starts assembled.
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
    /// The wordmark has faded in.
    @State private var markShown: Bool
    /// The wordmark has risen to its header rest.
    @State private var revealed: Bool
    /// How many deal controls have been revealed (0…`controlSlotCount`).
    @State private var revealedControls: Int
    /// Latches "this instance plays the intro" so it survives the view re-init
    /// that fires when `runIntro` sets the `introDone` binding (a plain `let`
    /// snapped the cascade).
    @State private var playsIntro: Bool
    @State private var introTask: Task<Void, Never>?

    @State private var showSettings = false
    @Environment(\.telemetry) private var telemetry

    /// The Reel total the player last *saw* on the pill, so growth since then can
    /// be shown rolling up rather than already there.
    @AppStorage(Self.reelShownKey) private var reelTotalShown = 0
    private static let reelShownKey = "reelTotalShown"
    /// What the pill displays while a roll-up is pending; `nil` = the live total.
    @State private var reelDisplayed: Int?
    /// Bumped to give the pill one small bump as its number rolls.
    @State private var reelBump = 0

    @AppStorage("soundEnabled") private var soundEnabled = true
    /// The first-run hint on the blank has played (it plays once, ever).
    @AppStorage("blankHintPlayed") private var blankHintPlayed = false
    /// Bumped to play that hint.
    @State private var blankNudge = 0
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(HandoffStage.self) private var stage: HandoffStage?

    /// Staggered slots for the intro cascade: the start(0), the blank(1),
    /// deal again / pick your own(2), the best run(3).
    private static let controlSlotCount = 4

    /// How long a dealt start must stay on screen before its candidates are
    /// prefetched — so a run of quick Deal agains doesn't fetch every one.
    private static let prefetchDelay: Duration = .milliseconds(400)

    init(engine: GameEngine, collection: CollectionStore, introDone: Binding<Bool>) {
        self.engine = engine
        self.collection = collection
        self._introDone = introDone
        let done = introDone.wrappedValue
        _playsIntro = State(initialValue: !done)
        _markShown = State(initialValue: done)
        _revealed = State(initialValue: done)
        _revealedControls = State(initialValue: done ? Self.controlSlotCount : 0)
        // Start the pill at the last-seen total (read here, not in `.task`, so
        // the first frame doesn't flash the new number before rolling back).
        let lastShown = UserDefaults.standard.integer(forKey: Self.reelShownKey)
        _reelDisplayed = State(initialValue: lastShown < collection.total ? lastShown : nil)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Theme.Spacing.lg) {
                // Animatable centering spacer for the intro; collapses to nothing
                // once the wordmark has risen.
                Color.clear.frame(height: topInset(geo.size.height))

                header

                Group {
                    if searching {
                        searchSection
                            .transition(modeSwap)
                    } else {
                        dealSection
                            .allowsHitTesting(!playsIntro || revealedControls == Self.controlSlotCount)
                            .transition(modeSwap)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.Color.canvas.ignoresSafeArea())
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
        // Each dealt start: warm its art (the avatar, the flight and the start
        // card all draw it), then, if it's still the one on screen, fetch its
        // candidates ahead of the tap.
        .task(id: engine.dealtSeed?.id) {
            guard let seed = engine.dealtSeed else { return }
            await ArtCache.shared.warm(seed)
            try? await Task.sleep(for: Self.prefetchDelay)
            guard !Task.isCancelled else { return }
            engine.prefetchCandidates(for: seed)
        }
        // Warm the haptic/audio engines HERE, on the seed screen, rather than in
        // GameView. `AVAudioEngine.start()` briefly blocks the main actor, and
        // doing it in GameView.task landed that block right on the seed->play
        // push. We wait until the entrance animation (cold-launch intro, or the
        // carousel push on a Play-again re-entry) has settled so the warm never
        // lands on an animation.
        .task(id: introRunning) { await warmFeedbackWhenIdle() }
        .task(id: introRunning) { await revealReelGrowth() }
        .task(id: "\(introRunning)-\(engine.dealtSeed == nil)") { await playBlankHint() }
        #if DEBUG
        // QA hook: tap the blank a moment after launch, to watch the handoff.
        .task(id: engine.dealtSeed == nil) {
            guard ProcessInfo.processInfo.arguments.contains("-uiAutoHandoff"),
                  engine.dealtSeed != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            startFromBlank()
        }
        #endif
        .onAppear {
            // swift-check:ignore on the next line — kept as a stored Task so `skipIntro`
            // can cancel it; the screen can't leave mid-intro (controls are inert).
            if introTask == nil { introTask = Task { await runIntro() } }  // swift-check:ignore
            #if DEBUG
            // Screenshot hook: open straight onto the Reel sheet.
            if ProcessInfo.processInfo.arguments.contains("-uiOpenReel") { showReel = true }
            #endif
        }
        .onChange(of: searching) { _, now in
            // Closing drops the keyboard at once (the search fades as it goes);
            // opening focuses only once the search has landed (below).
            guard !now else { return }
            searchFocused = false
            searchTask?.cancel(); query = ""; results = []
        }
        .task(id: searching) {
            guard searching else { return }
            try? await Task.sleep(for: Theme.Motion.swapSettle)
            guard !Task.isCancelled, searching else { return }
            searchFocused = true
        }
        #if DEBUG
        // QA hook: open the search flow a moment after launch, to watch the swap.
        .task(id: engine.dealtSeed == nil) {
            guard ProcessInfo.processInfo.arguments.contains("-uiOpenSearch"),
                  engine.dealtSeed != nil, !searching else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            searching = true
        }
        #endif
        .onDisappear {
            introTask?.cancel()
            searchTask?.cancel()
        }
    }

    /// The space above the header. During the intro it starts tall (the wordmark
    /// centered on the screen) and collapses as the rest assembles.
    private func topInset(_ height: CGFloat) -> CGFloat {
        revealed ? 0 : max(Theme.Spacing.xl, height * 0.36)
    }

    private var introRunning: Bool {
        playsIntro && revealedControls < Self.controlSlotCount
    }

    // MARK: Header — wordmark · Reel pill · settings
    //
    // The pills are an overlay, not siblings, so the wordmark can sit truly
    // centred during the intro; they fade out for the intro and the search flow.

    private var header: some View {
        Image("Wordmark")
            .resizable()
            .scaledToFit()
            .frame(height: 40)
            .scaleEffect(revealed ? 1 : 1.5)
            .opacity(markShown ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: revealed ? .leading : .center)
            .accessibilityLabel("Unspool")
            .accessibilityAddTraits(.isHeader)
            .overlay(alignment: .trailing) {
                HStack(spacing: Theme.Spacing.sm) {
                    reelButton
                    settingsButton
                }
                // Out with the layout they belong to, not trailing after it.
                .animation(Theme.Motion.layoutOut, value: pillsVisible)
            }
    }

    private var pillsVisible: Bool { !searching && !introRunning }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(Theme.Color.ink)
                .frame(width: 40, height: 40)
                .neoSurface(radius: Theme.Radius.pill, shadow: Theme.Shadow.small)
        }
        .buttonStyle(.pressScale)
        .opacity(pillsVisible ? 1 : 0)
        .disabled(!pillsVisible)
        .accessibilityLabel("Settings")
    }

    private var reelCount: Int { reelDisplayed ?? collection.total }

    // Always reachable (not gated on `collection.total > 0`): the Reel sheet holds
    // the required TMDB attribution, so a first-run player — who is already being
    // served TMDB-powered dealt seeds — must be able to open it before logging any
    // chain. The count only appears once there's something to count.
    private var reelButton: some View {
        Button {
            showReel = true
            telemetry?.reelOpened(from: .home)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "film.stack")
                    .font(Theme.Font.bodyStrong)
                if reelCount > 0 {
                    Text("\(reelCount)")
                        .font(Theme.Font.numeral(.headline))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(reelCount)))
                }
            }
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, reelCount > 0 ? Theme.Spacing.md : 0)
            .frame(minWidth: 40, minHeight: 40)
            .neoSurface(radius: Theme.Radius.pill, shadow: Theme.Shadow.small)
            // One small bump as the number rolls up. Reduce Motion: the
            // number still rolls, the pill holds still.
            .keyframeAnimator(initialValue: 1.0, trigger: reelBump) { [reduceMotion] view, scale in
                view.scaleEffect(reduceMotion ? 1 : scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.06, duration: 0.12)
                    SpringKeyframe(1.0, duration: 0.3, spring: .snappy)
                }
            }
        }
        .buttonStyle(.pressScale)
        .opacity(pillsVisible ? 1 : 0)
        .disabled(!pillsVisible)
        .accessibilityLabel(collection.total > 0 ? "Your Reel, \(collection.total) logged" : "Your Reel")
    }

    // MARK: Deal section — the sentence, its blank, deal again / pick your own

    private var dealSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Theme.Spacing.md)
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                cascade(sentenceHead, 0)
                cascade(blank, 1)
                cascade(dealLinks, 2)
                    .padding(.top, -Theme.Spacing.xs)
            }
            Spacer(minLength: Theme.Spacing.md)
            cascade(bestRun, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Deal ⇄ search: the leaving layout fades out fast, the arriving one fades
    /// in a beat later with a short rise (just the fade under Reduce Motion).
    private var modeSwap: AnyTransition {
        let arrive: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12))
        return .asymmetric(insertion: arrive.animation(Theme.Motion.layoutIn),
                           removal: .opacity.animation(Theme.Motion.layoutOut))
    }

    /// The flying pieces hide the moment the blank is tapped: the handoff's
    /// copies take their place in the same frame.
    private var handingOff: Bool { stage?.isFlying == true }

    // The start's half of the sentence. It sits in a fixed-height region, pinned
    // to the bottom, so the blank never moves: a short name leaves room above,
    // a long one grows up into it (and shrinks to fit three lines). Only this
    // part deals on a shuffle; the blank stays put.
    private var sentenceHead: some View {
        ZStack(alignment: .bottomLeading) {
            if let seed = engine.dealtSeed {
                SentenceHead(seed: seed, stage: stage)
                    .id(seed.id)
                    .transition(reduceMotion ? .opacity : .dealSentence)
            } else {
                Text("Dealing…")
                    .font(Theme.Font.flourish(size: SentenceType.verbSize))
                    .foregroundStyle(Theme.Color.muted)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .bottomLeading)
        .opacity(handingOff ? 0 : 1)
        .animation(reduceMotion ? Theme.Motion.reducedFade : Theme.Motion.drop, value: engine.dealtSeed)
    }

    // The blank is the start button: tapping it plays.
    private var blank: some View {
        Button(action: startFromBlank) {
            SentenceBlank(kind: engine.dealtSeed?.nextKind ?? .movie, nudge: blankNudge)
                .contentTransition(.opacity)
                .contentShape(Rectangle())
        }
        .buttonStyle(BlankButtonStyle())
        .disabled(engine.dealtSeed == nil || handingOff)
        .handoffSource(.blank, stage)
        .opacity(handingOff ? 0 : 1)
        .animation(Theme.Motion.standard, value: engine.dealtSeed?.nextKind)
        .accessibilityLabel(blankLabel)
    }

    private var blankLabel: String {
        guard let seed = engine.dealtSeed else { return "Dealing a start" }
        return seed.kind == .actor
            ? "Start: name a movie \(seed.matchText) was in"
            : "Start: name an actor who starred in \(seed.matchText)"
    }

    private var dealLinks: some View {
        HStack {
            Button {
                Haptics.selection()
                engine.shuffleSeed()
                telemetry?.dealt()
            } label: {
                Label("Deal again", systemImage: "shuffle")
            }
            .disabled(engine.dealtSeed == nil)

            Spacer(minLength: Theme.Spacing.sm)

            // The swap animates through its transitions (`modeSwap`).
            Button {
                searching = true
            } label: {
                Label("Pick your own", systemImage: "magnifyingglass")
            }
        }
        .buttonStyle(.pressScale)
        .labelStyle(LinkLabelStyle())
        .font(Theme.Font.bodyStrong)
        .foregroundStyle(Theme.Color.ink)
    }

    // The best run, centred at the foot of the screen — and nothing before
    // there is one. No "tap the blank": the sentence already reads
    // as the rule, and the blank's one-time nudge (`playBlankHint`) shows a new
    // player where to tap.
    @ViewBuilder private var bestRun: some View {
        if engine.bestChain > 0 {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("Best run").metaLabel()
                Text("\(Text("\(engine.bestChain)").font(Theme.Font.numeral(.title3)).foregroundStyle(Theme.Color.ink)) \(Text(engine.bestChain == 1 ? "link" : "links").font(Theme.Font.flourish(.body)))")
                    .foregroundStyle(Theme.Color.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private func startFromBlank() {
        // One handoff per run: the blank hides at opacity 0, which still takes
        // taps, and a second `begin` would start a flight with no frames to fly.
        guard !handingOff, let seed = engine.dealtSeed else { return }
        Haptics.selection()
        // Under Reduce Motion there's no flight: the screens just cross-fade.
        if !reduceMotion { stage?.begin(with: seed) }
        play()
    }

    private func play() {
        guard let seed = engine.dealtSeed else { return }
        searchTask?.cancel()
        telemetry?.runStarted(seed: seed, source: .dealt)
        Task { await engine.startGame(with: seed) }
    }

    // MARK: Search section — the demoted "pick your own start" flow

    private var searchSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                // The swap animates through its transitions (`modeSwap`).
                Button { searching = false } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Deal a start")
                    }
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressScale)
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

    // Empty state ⇄ results fades, the same way the layouts swap. Only that
    // swap: results replacing results as you type stay instant (they change on
    // every debounced keystroke, and fading those would read as lag).
    @ViewBuilder private var resultsSection: some View {
        if results.isEmpty {
            emptyState
                .transition(resultsSwap)
        } else {
            resultsList
                .transition(resultsSwap)
        }
    }

    private var resultsSwap: AnyTransition {
        .asymmetric(insertion: .opacity.animation(Theme.Motion.layoutIn),
                    removal: .opacity.animation(Theme.Motion.layoutOut))
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
        // Pinned to the top, not centred: centred, the keyboard coming up just
        // after the search lands slid it up a second time.
        .padding(.top, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        telemetry?.runStarted(seed: node, source: .picked)
        Task { await engine.startGame(with: node) }
    }

    // MARK: Intro sequence

    private func cascade<V: View>(_ view: V, _ index: Int) -> some View {
        view.modifier(ControlReveal(visible: revealedControls > index, enabled: playsIntro))
    }

    private func runIntro() async {
        if introDone || reduceMotion {
            markShown = true
            revealed = true
            revealedControls = Self.controlSlotCount
            introDone = true
            return
        }
        withAnimation(.easeOut(duration: 0.4)) { markShown = true }  // 1. wordmark fades up
        try? await Task.sleep(for: .milliseconds(850))
        if Task.isCancelled { return }
        withAnimation(Theme.Motion.intro) { revealed = true }        // 2. it rises to the header
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        for slot in 0..<Self.controlSlotCount {                      // 3. the rest deals in
            withAnimation(Theme.Motion.cascade) { revealedControls = slot + 1 }
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
        introDone = true                                             // (re-inits the view — last)
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

    /// After a run that grew the Reel, roll the pill's number up from what the
    /// player last saw to the new total, once the screen has landed — so the
    /// growth (the "look how many you know" hook) is seen, not just there.
    private func revealReelGrowth() async {
        guard !introRunning else { return }
        let total = collection.total
        guard let from = reelDisplayed, from < total else {
            reelTotalShown = total
            return
        }
        try? await Task.sleep(for: .seconds(Theme.Motion.screenSettle))
        guard !Task.isCancelled else { return }
        withAnimation(.snappy(duration: 0.4)) { reelDisplayed = nil }
        reelBump += 1
        reelTotalShown = total
    }

    /// Before a first game, once the screen has assembled and a start is dealt,
    /// point at the blank once: the arrow nudges toward play and the placeholder
    /// brightens. Never again after that, and never for someone with a best run.
    private func playBlankHint() async {
        guard !introRunning, engine.dealtSeed != nil,
              !blankHintPlayed, engine.bestChain == 0 else { return }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled, !searching, !handingOff else { return }
        blankNudge += 1
        blankHintPlayed = true
    }

    private func skipIntro() {
        guard playsIntro, !introDone else { return }
        introTask?.cancel()
        withAnimation(Theme.Motion.cascade) {
            markShown = true
            revealed = true
            revealedControls = Self.controlSlotCount
        }
        introDone = true
    }
}

// MARK: - The sentence

/// The dealt start's half of the sentence: avatar and kind chip, the name, and
/// "was in" / "starred". Each piece reports where it sits, keyed to this start,
/// so the handoff can fly it into the start card.
private struct SentenceHead: View {
    let seed: ChainNode
    let stage: HandoffStage?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm + 4) {
                HandoffArt(node: seed, radius: 20)
                    .frame(width: 40, height: 40)
                    .handoffSource(.art, stage, for: seed.id)
                KindChip(kind: seed.kind)
                    .handoffSource(.chip, stage, for: seed.id)
            }
            .padding(.bottom, Theme.Spacing.xs)
            SentenceName(text: seed.matchText)
                .handoffSource(.name, stage, for: seed.id)
            SentenceVerb(node: seed)
                .handoffSource(.verb, stage, for: seed.id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The blank's press: the arrow presses like every other bordered button (its
/// shadow collapses, it shifts into the page) and the row itself doesn't scale.
/// The tap's release is the flight's first frame, which draws the row at full
/// size — a scaled row would jump back on exactly that frame.
private struct BlankButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.blankPressed, configuration.isPressed)
    }
}

/// Icon and title as a quiet text link ("Deal again", "Pick your own").
private struct LinkLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            configuration.icon
            configuration.title
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }
}

// MARK: - Deal transition
//
// Deal again, as a card leaving the pile: the old start is flicked off to the
// leading side, turning as it goes, while the new one lands from just below —
// the same spring a chain card is dealt on in play. Reduce Motion uses a plain
// cross-fade.

private struct DealShift: ViewModifier {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var angle: Double = 0
    var scale: CGFloat = 1
    var opacity: Double = 1
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .bottomLeading)
            .rotationEffect(.degrees(angle), anchor: .bottomLeading)
            .offset(x: x, y: y)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var dealSentence: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: DealShift(y: 36, scale: 0.96, opacity: 0), identity: DealShift()),
            removal: .modifier(active: DealShift(x: -440, y: -16, angle: -8), identity: DealShift())
                .animation(Theme.Motion.dealOut)
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
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
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

#Preview {
    SeedView(engine: GameEngine(), collection: CollectionStore(fileURL: nil), introDone: .constant(true))
        .environment(HandoffStage())
}
