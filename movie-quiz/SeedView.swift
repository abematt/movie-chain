//
//  SeedView.swift
//  movie-quiz
//
//  The home screen. It leads with a *dealt start*, not a search box: the
//  Unspool wordmark with the Reel and settings pills, the player's best run (or,
//  before there is one, the game's question), then the start itself as a
//  physical card — the actor's headshot or the film's poster, the name, and the
//  rule for the next link ("Name a movie they were in"). The next link's kind
//  peeks out behind it in its accent colour. PLAY starts; Shuffle deals the card
//  away and a fresh one in; a quiet link drops down to the search flow for
//  players who want to pick their own.
//
//  The dealt seed is owned by the engine (`engine.dealtSeed`, refreshed on every
//  appearance and on resume). The card takes whatever height is left between
//  the header and the buttons (its art flexes, the name never moves), so the
//  same layout works from an SE to a Pro Max, and a deal never reflows the page.
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

    /// The Reel total the player last *saw* on the pill, so growth since then can
    /// be shown rolling up rather than already there.
    @AppStorage(Self.reelShownKey) private var reelTotalShown = 0
    private static let reelShownKey = "reelTotalShown"
    /// What the pill displays while a roll-up is pending; `nil` = the live total.
    @State private var reelDisplayed: Int?
    /// Bumped to give the pill one small bump as its number rolls.
    @State private var reelBump = 0

    @AppStorage("soundEnabled") private var soundEnabled = true
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Staggered slots for the intro cascade: best/tagline(0), card(1),
    /// shuffle + play(2), search link(3).
    private static let controlSlotCount = 4

    /// The TMDB size the dealt card draws (it is ~300pt wide, so `w185` is soft).
    static let dealtArtSize = "w500"

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
                    } else {
                        dealSection
                            .allowsHitTesting(!playsIntro || revealedControls == Self.controlSlotCount)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(Theme.Motion.standard, value: searching)
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
        // Pre-fetch each dealt start's art: the card's large size, and the small
        // one the first chain card draws, so it arrives with its art already in
        // place instead of loading in mid screen-push.
        .task(id: engine.dealtSeed?.id) {
            guard let seed = engine.dealtSeed else { return }
            async let card: Void = ArtCache.shared.warm(seed, size: Self.dealtArtSize)
            async let chain: Void = ArtCache.shared.warm(seed)
            _ = await (card, chain)
        }
        // Warm the haptic/audio engines HERE, on the seed screen, rather than in
        // GameView. `AVAudioEngine.start()` briefly blocks the main actor, and
        // doing it in GameView.task landed that block right on the seed->play
        // push. We wait until the entrance animation (cold-launch intro, or the
        // carousel push on a Play-again re-entry) has settled so the warm never
        // lands on an animation.
        .task(id: introRunning) { await warmFeedbackWhenIdle() }
        .task(id: introRunning) { await revealReelGrowth() }
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
            // Focus the field when the search flow opens; drop it when it closes.
            searchFocused = now
            if !now { searchTask?.cancel(); query = ""; results = [] }
        }
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
                .animation(Theme.Motion.standard, value: pillsVisible)
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
        Button { showReel = true } label: {
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

    // MARK: Deal section — best run, the dealt card, Shuffle + Play, search link

    private var dealSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            cascade(bestOrTagline, 0)
            cascade(dealtCard, 1)
                .frame(maxHeight: .infinity)
            VStack(spacing: Theme.Spacing.md) {
                cascade(actionRow, 2)
                cascade(searchLink, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The best run, once there is one. Before that, the game's question — the
    /// one line of "what is this" a first-time player gets.
    @ViewBuilder private var bestOrTagline: some View {
        if engine.bestChain > 0 {
            HStack(alignment: .firstTextBaseline) {
                Text("Your best").metaLabel()
                Spacer(minLength: Theme.Spacing.sm)
                Text("\(Text("\(engine.bestChain)").font(Theme.Font.numeral(.title2)).foregroundStyle(Theme.Color.ink)) \(Text(engine.bestChain == 1 ? "link" : "links").font(Theme.Font.flourish(.body))) · \(engine.bestPoints) pts")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Theme.Spacing.md + 4)
            .padding(.vertical, Theme.Spacing.md - 2)
            .neoSurface(radius: Theme.Radius.card, shadow: Theme.Shadow.small)
            .accessibilityElement(children: .combine)
        } else {
            Text("How long can you keep the chain alive?")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // The start as a card on a pile: the next link's kind peeks out behind it.
    // Only the front card deals; the one behind stays put and recolours, so a
    // shuffle reads as one card leaving the top of the pile and a new one landing.
    private var dealtCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.card + 4)
                .fill(engine.dealtSeed?.nextKind.accent ?? Theme.Color.hairline)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card + 4)
                    .strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
                .padding(.vertical, Theme.Spacing.md)
                .rotationEffect(.degrees(5))
                .offset(x: Theme.Spacing.sm)
                .animation(Theme.Motion.standard, value: engine.dealtSeed?.nextKind)
                .accessibilityHidden(true)

            Group {
                if let seed = engine.dealtSeed {
                    Button { play() } label: { DealtCardFace(seed: seed) }
                        .buttonStyle(.pressScale)
                        .accessibilityLabel("Start with \(seed.matchText), \(seed.kind == .actor ? "actor" : "movie")")
                        .accessibilityHint(seed.nextKind.prompt)
                        .id(seed.id)
                        .transition(reduceMotion ? .opacity : .dealCard)
                } else {
                    DealingCardFace()
                        .transition(.opacity)
                }
            }
            .rotationEffect(.degrees(-2))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .animation(reduceMotion ? Theme.Motion.reducedFade : Theme.Motion.drop, value: engine.dealtSeed)
    }

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                Haptics.selection()
                engine.shuffleSeed()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3.weight(.bold))
                    .padding(.vertical, Theme.Spacing.md - 2)
            }
            .buttonStyle(.ghost)
            .frame(width: 72)
            .disabled(engine.dealtSeed == nil)
            .accessibilityLabel("Shuffle")

            Button { play() } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Play")
                    Image(systemName: "arrow.right")
                }
                .font(.title3.weight(.heavy))
                .padding(.vertical, Theme.Spacing.md - 2)
            }
            .buttonStyle(.primary)
            .disabled(engine.dealtSeed == nil)
        }
    }

    private var searchLink: some View {
        Button {
            withAnimation(Theme.Motion.standard) { searching = true }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                Text("Or search for your own start")
            }
            .font(Theme.Font.bodyStrong)
            .foregroundStyle(Theme.Color.ink)
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
    }

    private func play() {
        guard let seed = engine.dealtSeed else { return }
        searchTask?.cancel()
        Task { await engine.startGame(with: seed) }
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

// MARK: - The dealt card

/// The front of the dealt start: kind chip and "START WITH", the art (which
/// takes whatever height the card is given), the name, and the next link's rule.
private struct DealtCardFace: View {
    let seed: ChainNode

    var body: some View {
        DealtCardShell {
            HStack {
                KindChip(kind: seed.kind)
                Spacer()
                Text("Start with").metaLabel()
            }
            DealtArt(node: seed)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(seed.matchText)                     // bare name/title, no year
                    .font(Theme.Font.display(34))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)             // shrink to fit, never clip
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                    Text(seed.nextKind.prompt)
                }
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The card while the first deal is still loading — same shell, so the page
/// doesn't move when the real card lands.
private struct DealingCardFace: View {
    var body: some View {
        DealtCardShell {
            HStack {
                Spacer()
                Text("Start with").metaLabel()
            }
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Color.hairline)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
            Text("Dealing…")
                .font(Theme.Font.flourish(size: 28))
                .foregroundStyle(Theme.Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DealtCardShell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            content
        }
        .padding(Theme.Spacing.md + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neoSurface(radius: Theme.Radius.card + 4)
    }
}

/// The dealt card's art at a size that holds up ~300pt wide. Drawn at once if
/// the home already warmed it, else loaded through `ArtCache` and faded in.
/// Faces sit near the top of a headshot, so the crop keeps the top.
private struct DealtArt: View {
    let node: ChainNode
    @State private var loaded: Image?

    private var url: URL? { Config.imageURL(path: node.imagePath, size: SeedView.dealtArtSize) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md)
        let image = loaded ?? url.flatMap(ArtCache.shared.image(for:))
        node.accent
            .overlay(alignment: .top) {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: node.symbol)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(node.kind.onAccent.opacity(0.75))
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(minHeight: 80)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
            .accessibilityHidden(true)
            .task(id: url) {
                guard loaded == nil, let url else { return }
                let image = await ArtCache.shared.load(url)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) { loaded = image }
            }
    }
}

// MARK: - Deal transition
//
// Shuffle as a card leaving the pile: the old start is flicked off to the
// leading side, turning as it goes, while the new one lands on the pile from
// just below — the same spring a chain card is dealt on in play. Reduce Motion
// uses a plain cross-fade.

private struct DealShift: ViewModifier {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var angle: Double = 0
    var scale: CGFloat = 1
    var opacity: Double = 1
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var dealCard: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: DealShift(y: 40, scale: 0.94, opacity: 0), identity: DealShift()),
            removal: .modifier(active: DealShift(x: -420, y: -20, angle: -14), identity: DealShift())
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
}
