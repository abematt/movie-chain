//
//  CoinStack.swift
//  movie-quiz
//
//  A finished chain drawn as one continuous stack of coins: the start at the
//  bottom, each link a coin on top of the last. A coin is one solid colour, face
//  and side — blue for an actor, yellow for a movie — with an ink line between
//  coins, and only the top coin shows its face. When the top coin is a movie it
//  is a film spool: sprocket holes along its side and reel holes in its face.
//  Actors are labelled on the left, movies on the right.
//
//  Game over draws it, and the share card. Drawn in one `Canvas`, so a long
//  chain is one layer, not a view per coin; the stack squeezes its spacing to
//  fit the height it's given, and thins its labels when they'd collide.
//
//  On game over the stack opens under a finger (after hairline's stack figure):
//  drag up and down it. The finger's height picks a link, the coins
//  above it lift away — the top one furthest — so its face shows, and its label
//  gains the film's year. The lifts are tweens on the stack's own clock, each
//  retargeted from wherever it is, so sliding fast never jumps; the clock runs
//  only while a coin is moving. Letting go settles the coins back down.
//

import SwiftUI

struct CoinStack: View {
    let chain: [ChainNode]
    /// Label colour: white on Night, ink on the holo sky.
    var labelColor: Color = .white
    /// Draw the top coin as a film spool when it's a movie.
    var film = true
    /// Name each coin. Off on the share card, which mustn't spoil the route.
    var labels = true
    /// Opens under a finger. Off on the share card, which is a still image.
    var interactive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The coin the finger is on; nil when the stack is closed.
    @State private var chosen: Int?
    /// The coin whose face shows under the lifted coins: the chosen one, kept
    /// while the coins settle back onto it after the finger lifts.
    @State private var faced: Int?
    @State private var lifts: [Tween] = []
    /// When the last coin settles; the clock stops after it.
    @State private var settles = Date.distantPast
    @State private var moving = false
    @State private var size: CGSize = .zero

    /// A coin, in points: its face, and the thickness of its side.
    static let width: CGFloat = 116
    static let faceHeight: CGFloat = 38
    static let thickness: CGFloat = 10
    /// The most the coins are spaced; a long chain packs tighter.
    static let maxStep: CGFloat = 20
    /// Labels closer than this would collide, so some are skipped.
    static let labelGap: CGFloat = 15
    /// Past the first lifted coin, each one above lifts this much further, at most.
    static let spread: CGFloat = 5

    var body: some View {
        TimelineView(.animation(paused: !moving)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, lift: liftValues(at: timeline.date))
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        // A drag straight on the stack scrubs it; the screen scrolls from anywhere else.
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { press(chosen == nil ? .began : .moved, y: $0.location.y) }
            .onEnded { press(.ended, y: $0.location.y) },
                 including: interactive ? .all : .subviews)
        .task(id: settles) {
            // Stop the clock once the last coin has landed.
            let wait = settles.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            moving = false
        }
        #if DEBUG
        // `-uiStackOpen N` (DEBUG) opens the stack at link N, to check it without a finger.
        .task {
            let open = UserDefaults.standard.integer(forKey: "uiStackOpen")
            guard interactive, open > 0, open < chain.count else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            choose(open)
        }
        #endif
        .accessibilityElement()
        .accessibilityLabel("Your chain: " + chain.map(\.matchText).joined(separator: ", "))
    }

    // MARK: Opening

    /// One coin's lift: from where it was to where it's going, starting after its stagger.
    struct Tween {
        var from: CGFloat = 0, to: CGFloat = 0
        var start = Date.distantPast, duration: Double = 0

        func value(at date: Date) -> CGFloat {
            guard duration > 0 else { return to }
            let p = min(1, max(0, date.timeIntervalSince(start) / duration))
            return from + (to - from) * CGFloat(Theme.Motion.stackLiftCurve.value(at: p))
        }
    }

    private func liftValues(at date: Date) -> [CGFloat] {
        guard lifts.count == chain.count else { return Array(repeating: 0, count: chain.count) }
        var values = lifts.map { $0.value(at: date) }
        // A coin is never higher than the one on it — mid-flight, retargeted
        // tweens could otherwise cross, and a coin would show through another.
        for j in values.indices.dropFirst() { values[j] = max(values[j], values[j - 1]) }
        return values
    }

    private func press(_ phase: StackPress.Phase, y: CGFloat) {
        guard interactive else { return }
        switch phase {
        case .began, .moved: choose(hit(y))
        case .ended: choose(nil)
        }
    }

    /// Opens the stack at coin `a` (nil closes it). The stagger spreads out from
    /// the coin chosen, or the one let go.
    private func choose(_ a: Int?) {
        guard a != chosen else { return }
        let from = a ?? chosen ?? 0
        chosen = a
        if a != nil { faced = a; Haptics.selection() }
        let now = Date()
        let duration = reduceMotion ? 0 : (a == nil ? Theme.Motion.stackClose : Theme.Motion.stackOpen)
        let geometry = Self.layout(count: chain.count, height: usableHeight, interactive: true)
        if lifts.count != chain.count { lifts = Array(repeating: Tween(), count: chain.count) }
        var last = now
        for j in chain.indices {
            let current = lifts[j].value(at: now)
            let target = Self.lift(j, chosen: a, count: chain.count, step: geometry.step)
            guard target != lifts[j].to else { continue }
            // Staggered up the stack from the coin chosen; the coins below it move
            // together. A stagger downwards too would land a coin after the one
            // above it, and it would show through.
            let delay = reduceMotion ? 0 : Double(max(j - from, 0)) * Theme.Motion.stackStagger
            lifts[j] = Tween(from: current, to: target, start: now.addingTimeInterval(delay), duration: duration)
            last = max(last, now.addingTimeInterval(delay + duration))
        }
        settles = last
        moving = true
    }

    /// How far coin `j` stands above its place with coin `a` chosen: the first
    /// coin above clears the chosen face, each one after a little further.
    private static func lift(_ j: Int, chosen a: Int?, count: Int, step: CGFloat) -> CGFloat {
        guard let a, j > a else { return 0 }
        return firstLift(step: step) + spread(count: count) * CGFloat(j - a - 1)
    }

    private static func firstLift(step: CGFloat) -> CGFloat { faceHeight + thickness - step + 4 }
    private static func spread(count: Int) -> CGFloat { min(spread, 24 / CGFloat(max(count - 2, 1))) }

    /// The coin whose resting band holds `y`, the nearest one when outside it.
    private func hit(_ y: CGFloat) -> Int {
        let g = Self.layout(count: chain.count, height: usableHeight, interactive: interactive)
        let coin = Self.faceHeight + Self.thickness
        var best = 0, distance = CGFloat.infinity
        for i in chain.indices {
            let top = g.bottomTop - CGFloat(i) * g.step
            let mid = i == chain.count - 1 ? top + coin / 2 : top + coin - g.step / 2
            // Keep the current coin until the finger is clearly on another.
            if i == chosen, abs(y - mid) <= g.step / 2 + 5 { return i }
            if abs(y - mid) < distance { distance = abs(y - mid); best = i }
        }
        return best
    }

    /// Room for the outline's outer half, so the bottom coin isn't clipped.
    private var usableHeight: CGFloat { size.height - Theme.Border.width }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, lift: [CGFloat]) {
        guard !chain.isEmpty else { return }
        let w = Self.width, h = Self.faceHeight, t = Self.thickness
        let left = (size.width - w) / 2
        let coinHeight = h + t
        let g = Self.layout(count: chain.count, height: size.height - Theme.Border.width, interactive: interactive)
        let step = g.step
        let every = Int((Self.labelGap / max(step, 1)).rounded(.up))
        let line = Theme.Color.night
        let lineWidth = Theme.Border.width

        for (i, node) in chain.enumerated() {
            let top = g.bottomTop - CGFloat(i) * step - lift[i]
            let colour = node.kind.accent
            let isTop = i == chain.count - 1
            // Only two faces ever show: the top coin's, and the chosen coin's once
            // the coins above are half a coin off it. Any other coin a gap opens
            // over just reads a little thicker, not as a second disc.
            let uncovered = isTop || (i == faced && lift[i + 1] - lift[i] > t / 2)
            // Each coin is a band with elliptical ends; the next one up covers
            // all of it but the bottom sliver, which reads as this coin's side.
            let band = Self.coin(left: left, top: top)
            context.fill(band, with: .color(colour))
            context.stroke(band, with: .color(line), lineWidth: lineWidth)

            if isTop, film, node.kind == .movie { drawSprockets(in: &context, left: left, top: top) }
            if uncovered {
                let face = Path(ellipseIn: CGRect(x: left, y: top, width: w, height: h))
                context.fill(face, with: .color(colour))
                context.stroke(face, with: .color(line), lineWidth: lineWidth)
                if isTop, film, node.kind == .movie { drawReelFace(in: &context, left: left, top: top) }
            }

            // Thin the labels on a tight stack, but always name the start, the
            // top and the coin chosen.
            let isChosen = i == chosen
            guard labels, i == 0 || isTop || isChosen || i % every == 0 else { continue }
            // A coin shows only its bottom sliver under the next one, so its label
            // points at that sliver; a whole coin's label points at its middle.
            let resting = isTop ? top + coinHeight / 2 : top + coinHeight - step / 2
            let mid = isChosen ? top + h / 2 : resting
            let dim = chosen != nil && !isChosen
            drawLabel(node, year: isChosen, in: &context, left: left, mid: mid, size: size, dimmed: dim)
        }
    }

    /// Where the stack sits in `height`: the gap between coins, and the top of
    /// the bottom coin. With `interactive`, room is kept above it for the coins
    /// to lift into.
    static func layout(count: Int, height: CGFloat, interactive: Bool = false) -> (step: CGFloat, bottomTop: CGFloat) {
        let coin = faceHeight + thickness
        let roomy = step(count: count, height: height)
        let headroom = interactive && count > 1
            ? firstLift(step: roomy) + spread(count: count) * CGFloat(max(count - 2, 0)) : 0
        let gap = step(count: count, height: height - headroom)
        let natural = coin + CGFloat(max(count - 1, 0)) * gap
        // A short stack sits in the middle of its space, but never so high its
        // coins can't lift.
        let bottom = max(height - max(0, (height - natural) / 2), min(height, headroom + natural))
        return (gap, bottom - coin)
    }

    /// A coin's outline: the face's top half, straight sides as deep as the
    /// coin is thick, and the face's bottom half below them. Built from the same
    /// quarter-ellipse curves `Path(ellipseIn:)` uses, so its top meets the top
    /// coin's face exactly; a rounded rectangle's corners don't, and leaked this
    /// coin's colour around the one above.
    static func coin(left: CGFloat, top: CGFloat) -> Path {
        let rx = width / 2, ry = faceHeight / 2, t = thickness
        let k: CGFloat = 0.5523  // a quarter ellipse as one cubic
        let cx = left + rx, right = left + width
        let upper = top + ry, lower = top + ry + t
        var p = Path()
        p.move(to: CGPoint(x: left, y: upper))
        p.addCurve(to: CGPoint(x: cx, y: top),
                   control1: CGPoint(x: left, y: upper - k * ry), control2: CGPoint(x: cx - k * rx, y: top))
        p.addCurve(to: CGPoint(x: right, y: upper),
                   control1: CGPoint(x: cx + k * rx, y: top), control2: CGPoint(x: right, y: upper - k * ry))
        p.addLine(to: CGPoint(x: right, y: lower))
        p.addCurve(to: CGPoint(x: cx, y: lower + ry),
                   control1: CGPoint(x: right, y: lower + k * ry), control2: CGPoint(x: cx + k * rx, y: lower + ry))
        p.addCurve(to: CGPoint(x: left, y: lower),
                   control1: CGPoint(x: cx - k * rx, y: lower + ry), control2: CGPoint(x: left, y: lower + k * ry))
        p.closeSubpath()
        return p
    }

    /// Where the stack's bottom edge sits: centred in `height` when the stack is
    /// shorter than it, on the floor when it fills it.
    static func floor(count: Int, height: CGFloat) -> CGFloat {
        layout(count: count, height: height).bottomTop + faceHeight + thickness
    }

    /// How far apart the coins sit for `count` coins in `height` points.
    static func step(count: Int, height: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        return min(maxStep, max(2, (height - faceHeight - thickness) / CGFloat(count - 1)))
    }

    /// The vertical middle of the start coin and of the top coin, for a stack of
    /// `count` coins drawn `height` tall — where a pointer to either should aim.
    static func ends(count: Int, height: CGFloat) -> (start: CGFloat, top: CGFloat) {
        let coin = faceHeight + thickness
        let height = height - Theme.Border.width
        let gap = step(count: count, height: height)
        let bottom = floor(count: count, height: height)
        let top = bottom - coin - CGFloat(max(count - 1, 0)) * gap + coin / 2
        // Under the others, the start shows only its bottom sliver.
        let start = count > 1 ? bottom - gap / 2 : top
        return (start, top)
    }

    /// Sprocket holes riding the top coin's visible side, following its curve.
    private func drawSprockets(in context: inout GraphicsContext, left: CGFloat, top: CGFloat) {
        let rx = Self.width / 2, ry = Self.faceHeight / 2, t = Self.thickness
        let cx = left + rx
        for dx in stride(from: -45.0, through: 45.0, by: 10.0) {
            let edge = top + Self.faceHeight + t - ry + ry * sqrt(1 - pow(dx / rx, 2))
            let hole = CGRect(x: cx + dx - 2.5, y: edge - t / 2 - 2, width: 5, height: 4)
            context.fill(Path(roundedRect: hole, cornerRadius: 1.5), with: .color(Theme.Color.night))
        }
    }

    /// The reel's face: five spoke holes round a hub, squashed into the ellipse.
    private func drawReelFace(in context: inout GraphicsContext, left: CGFloat, top: CGFloat) {
        let rx = Self.width / 2, ry = Self.faceHeight / 2
        let cx = left + rx, cy = top + ry
        let ink = GraphicsContext.Shading.color(Theme.Color.night)
        context.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 2, width: 10, height: 4)), with: ink)
        for k in 0..<5 {
            let a = (-90 + 72 * Double(k)) * .pi / 180
            let x = cx + 0.58 * rx * cos(a), y = cy + 0.58 * ry * sin(a)
            context.fill(Path(ellipseIn: CGRect(x: x - 9, y: y - 3.5, width: 18, height: 7)), with: ink)
        }
    }

    /// Actors to the left of the stack, movies to the right, each with a short
    /// leader line to its coin. The chosen film also gives its year; the rest
    /// dim while one is chosen.
    private func drawLabel(_ node: ChainNode, year: Bool, in context: inout GraphicsContext,
                           left: CGFloat, mid: CGFloat, size: CGSize, dimmed: Bool) {
        let onLeft = node.kind == .actor
        let room = (onLeft ? left : size.width - left - Self.width) - 20
        guard room > 30 else { return }
        let colour = labelColor.opacity(dimmed ? 0.38 : 1)
        var label = Text(node.matchText).font(Theme.Font.coinLabel).foregroundStyle(colour)
        if year, case .movie(let m) = node, let y = m.year {
            label = label + Text(" " + String(y)).font(Theme.Font.coinLabel.bold()).foregroundStyle(colour)
        }
        let text = context.resolve(label)
        // Up to two lines, so a long name wraps rather than truncating.
        let measured = text.measure(in: CGSize(width: room, height: 34))
        // A two-line label on the start coin mustn't run off the bottom.
        let mid = min(mid, size.height - measured.height / 2)
        let leader: CGFloat = 12
        let gap: CGFloat = 4
        var rule = Path()
        if onLeft {
            rule.move(to: CGPoint(x: left - gap - leader, y: mid))
            rule.addLine(to: CGPoint(x: left - gap, y: mid))
            context.draw(text, in: CGRect(x: left - gap - leader - 6 - measured.width, y: mid - measured.height / 2,
                                          width: measured.width, height: measured.height))
        } else {
            let right = left + Self.width
            rule.move(to: CGPoint(x: right + gap, y: mid))
            rule.addLine(to: CGPoint(x: right + gap + leader, y: mid))
            context.draw(text, in: CGRect(x: right + gap + leader + 6, y: mid - measured.height / 2,
                                          width: measured.width, height: measured.height))
        }
        context.stroke(rule, with: .color(colour), lineWidth: 1.5)
    }
}

/// What the finger is doing on the stack.
private enum StackPress {
    enum Phase { case began, moved, ended }
}

#Preview("Coin stack") {
    CoinStack(chain: [
        .actor(Person(id: 1, name: "Brad Pitt")),
        .movie(Movie(id: 1001, title: "Ocean's Eleven", year: 2001)),
        .actor(Person(id: 2, name: "Matt Damon")),
        .movie(Movie(id: 1002, title: "The Departed", year: 2006)),
    ])
    .frame(height: 300)
    .padding()
    .background(Theme.Color.night)
}
