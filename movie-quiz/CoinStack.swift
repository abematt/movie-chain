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
//  Game over draws it, and the share card will. Drawn in one `Canvas`, so a long
//  chain is one layer, not a view per coin; the stack squeezes its spacing to
//  fit the height it's given, and thins its labels when they'd collide.
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

    /// A coin, in points: its face, and the thickness of its side.
    static let width: CGFloat = 116
    static let faceHeight: CGFloat = 38
    static let thickness: CGFloat = 10
    /// The most the coins are spaced; a long chain packs tighter.
    static let maxStep: CGFloat = 20
    /// Labels closer than this would collide, so some are skipped.
    static let labelGap: CGFloat = 15

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .accessibilityElement()
        .accessibilityLabel("Your chain: " + chain.map(\.matchText).joined(separator: ", "))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard !chain.isEmpty else { return }
        let w = Self.width, h = Self.faceHeight, t = Self.thickness
        let left = (size.width - w) / 2
        let coinHeight = h + t
        let step = Self.step(count: chain.count, height: size.height)
        let bottomTop = size.height - coinHeight
        let every = Int((Self.labelGap / max(step, 1)).rounded(.up))
        let line = Theme.Color.night
        let lineWidth = Theme.Border.width

        for (i, node) in chain.enumerated() {
            let top = bottomTop - CGFloat(i) * step
            let colour = node.kind.accent
            let isTop = i == chain.count - 1
            // Each coin is a band with elliptical ends; the next one up covers
            // all of it but the bottom sliver, which reads as this coin's side.
            let band = Path(roundedRect: CGRect(x: left, y: top, width: w, height: coinHeight),
                            cornerSize: CGSize(width: w / 2, height: h / 2))
            context.fill(band, with: .color(colour))
            context.stroke(band, with: .color(line), lineWidth: lineWidth)

            if isTop {
                if film, node.kind == .movie { drawSprockets(in: &context, left: left, top: top) }
                let face = Path(ellipseIn: CGRect(x: left, y: top, width: w, height: h))
                context.fill(face, with: .color(colour))
                context.stroke(face, with: .color(line), lineWidth: lineWidth)
                if film, node.kind == .movie { drawReelFace(in: &context, left: left, top: top) }
            }

            // Thin the labels on a tight stack, but always name the start and the top.
            guard labels, i == 0 || isTop || i % every == 0 else { continue }
            // A coin shows only its bottom sliver under the next one, so its label
            // points at that sliver; the top coin is whole, so it points at its middle.
            let mid = isTop ? top + coinHeight / 2 : top + coinHeight - step / 2
            drawLabel(node, in: &context, left: left, mid: mid, size: size)
        }
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
        let gap = step(count: count, height: height)
        let top = height - coin - CGFloat(max(count - 1, 0)) * gap + coin / 2
        // Under the others, the start shows only its bottom sliver.
        let start = count > 1 ? height - gap / 2 : top
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
    /// leader line to its coin.
    private func drawLabel(_ node: ChainNode, in context: inout GraphicsContext,
                           left: CGFloat, mid: CGFloat, size: CGSize) {
        let onLeft = node.kind == .actor
        let room = (onLeft ? left : size.width - left - Self.width) - 20
        guard room > 30 else { return }
        let text = context.resolve(Text(node.matchText)
            .font(Theme.Font.small)
            .foregroundStyle(labelColor))
        // Up to two lines, so a long name wraps rather than truncating.
        let measured = text.measure(in: CGSize(width: room, height: 34))
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
        context.stroke(rule, with: .color(labelColor), lineWidth: 1.5)
    }
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
