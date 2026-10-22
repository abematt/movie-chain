//
//  ArtCache.swift
//  movie-quiz
//
//  A tiny in-memory cache for the art of the *dealt start*. The home screen warms
//  it as each start is dealt, so when the player taps Start the first chain card
//  draws its poster/headshot synchronously — already in place as the play screen
//  slides in, with nothing loading (and nothing animating) mid-push.
//
//  Only the dealt start is known ahead of time; every later link's art still
//  streams through `AsyncImage` in `ChainArt`. Kept deliberately small: the
//  last few deals, decoded once, never written to disk.
//

import SwiftUI
import ImageIO

@MainActor
final class ArtCache {
    static let shared = ArtCache()

    /// How many decoded images to keep — a handful of recent deals is plenty.
    private let capacity = 8
    private var images: [URL: Image] = [:]
    private var order: [URL] = []

    /// The cached art for `url`, if this node was warmed.
    func image(for url: URL) -> Image? { images[url] }

    /// Download and decode `node`'s art so `ChainArt` can draw it at once.
    /// Silent on failure: the card simply falls back to `AsyncImage`.
    func warm(_ node: ChainNode) async {
        guard let url = Config.imageURL(path: node.imagePath, size: "w185"),
              images[url] == nil,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let cgImage = await Self.decode(data)
        else { return }
        images[url] = Image(decorative: cgImage, scale: 1)
        order.append(url)
        if order.count > capacity {
            images[order.removeFirst()] = nil
        }
    }

    /// Off-main decode, `@concurrent` for the same reason as `TMDBProvider.decode`:
    /// a plain `nonisolated async` function would run on the caller's actor (Main).
    @concurrent
    nonisolated private static func decode(_ data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
