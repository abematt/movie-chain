//
//  ShareCard.swift
//  movie-quiz
//
//  The image a share sends with its text: the run on Night, as the link count
//  and the coin stack, and the start to beat it from. Spoiler-free — the coins
//  carry no names, only where the run started and how far it got — because the
//  start is the dare: a friend plays from the same one.
//
//  Drawn with `ImageRenderer` at 9:16 (1080 × 1920 at 3×), the shape stories and
//  messages both show whole. Always dark, whatever the phone's appearance.
//

import SwiftUI

struct ShareCard: View {
    let chain: [ChainNode]
    let links: Int
    var date: Date = .now

    /// Points, not pixels: rendered at 3×.
    static let size = CGSize(width: 360, height: 640)

    private static let rule = Theme.Color.ruleOnNight
    private static let quiet = Theme.Color.quietOnNight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Unspool · \(date.formatted(.dateTime.day().month(.abbreviated)))")
                .metaLabel(Self.quiet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(Self.rule).frame(height: 1) }

            HStack(alignment: .bottom, spacing: 10) {
                Text("\(links)")
                    .font(Theme.Font.display(166))
                    .padding(.bottom, -28)
                Text(links == 1 ? "link" : "links")
                    .font(Theme.Font.display(27))
                    .textCase(.uppercase)
                    .tracking(Theme.Font.buttonTracking)
                    .padding(.bottom, 8)
            }
            .padding(.top, Theme.Spacing.lg)

            stack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, Theme.Spacing.lg)

            footer
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.Color.night)
        .environment(\.colorScheme, .dark)
    }

    // The stack with two pointers off its right side: the top coin ("Link 13")
    // and the start.
    private var stack: some View {
        GeometryReader { geo in
            let ends = CoinStack.ends(count: chain.count, height: geo.size.height)
            let right = (geo.size.width + CoinStack.width) / 2
            CoinStack(chain: chain, labels: false, interactive: false)
            if chain.count > 1 {
                pointer("Link \(links)", colour: Self.quiet)
                    .position(x: right + 52, y: ends.top)
            }
            pointer("Start", colour: .white)
                .position(x: right + 52, y: ends.start)
        }
    }

    private func pointer(_ label: String, colour: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(colour).frame(width: 24, height: 1.5)
            Text(label).metaLabel(colour, size: .small)
        }
        .fixedSize()
        .frame(width: 96, alignment: .leading)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start from").metaLabel(Self.quiet, size: .small)
                Text(chain.first?.matchText ?? "")
                    .font(Theme.Font.heading(.title2))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: Theme.Spacing.md)
            Image("Wordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 22)
                .accessibilityLabel("Unspool")
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(Self.rule).frame(height: 1) }
    }

    /// The card as a picture, for the share sheet.
    @MainActor static func image(chain: [ChainNode], links: Int) -> Image? {
        let renderer = ImageRenderer(content: ShareCard(chain: chain, links: links))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

#Preview {
    ShareCard(chain: [
        .actor(Person(id: 1, name: "Brad Pitt")),
        .movie(Movie(id: 1001, title: "Ocean's Eleven", year: 2001)),
        .actor(Person(id: 2, name: "Matt Damon")),
        .movie(Movie(id: 1002, title: "The Departed", year: 2006)),
    ], links: 3)
}
