//
//  ArtCache.swift
//  movie-quiz
//
//  The app's in-memory cache of decoded posters and headshots. Two jobs:
//
//  • The dealt start. The home screen warms its art as each start is dealt, so
//    when the player taps Start the first chain card draws it synchronously —
//    already in place as the play screen slides in, with nothing loading (and
//    nothing animating) mid-push.
//  • Your Reel. Every card and frame reads through here, so reopening the Reel
//    draws its art at once instead of every card fading in again, and a lifted
//    card shows the image its grid slot already had. The first screen of the Reel
//    is warmed at launch, so even the first open arrives with its art.
//
//  `AsyncImage` keeps no memory cache, which is why it isn't used for these.
//  Downloads go through a session whose disk cache is sized for art (the shared
//  one holds ~10MB), images decode off the main actor, and decoded images live
//  in an `NSCache` bounded by bytes, so memory pressure evicts rather than grows.
//  Never written anywhere but the URL cache.
//
//  An actor card's duotone (`Duotone`) is baked in during that same off-main
//  decode and cached as its own image, keyed by the URL plus the pair
//  (`key(_:duotone:)`), so a tinted photo costs nothing to draw.
//

import SwiftUI
import ImageIO

@MainActor
final class ArtCache {
    static let shared = ArtCache()

    private let images = NSCache<NSURL, CachedImage>()
    /// The most recently used images, held strongly on top of the `NSCache`,
    /// which may drop entries whenever the system likes. These are the ones on
    /// screen now — the Reel re-creates a card as it lifts and lands, and a
    /// copy that found its art evicted started blank, flashing its accent.
    private var recent: [URL: Image] = [:]
    private var recentOrder: [URL] = []
    private let recentCapacity = 64
    /// One in-flight load per URL, so a grid card and its lifted copy — or a
    /// warm and a card appearing — share a single download.
    private var loading: [URL: Task<Image?, Never>] = [:]
    private let session: URLSession

    private init() {
        images.totalCostLimit = 80 * 1024 * 1024      // decoded bytes
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 150 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad   // TMDB art never changes at a URL
        config.timeoutIntervalForRequest = Config.requestTimeout
        session = URLSession(configuration: config)
    }

    /// The decoded art for `url`, if it's in memory — for drawing synchronously.
    func image(for url: URL) -> Image? {
        if let hit = recent[url] ?? images.object(forKey: url as NSURL)?.image {
            remember(hit, for: url)
            return hit
        }
        return nil
    }

    /// Mark `url` most recently used, dropping the oldest past capacity.
    private func remember(_ image: Image, for url: URL) {
        if recent.updateValue(image, forKey: url) != nil {
            recentOrder.removeAll { $0 == url }
        }
        recentOrder.append(url)
        if recentOrder.count > recentCapacity {
            recent[recentOrder.removeFirst()] = nil
        }
    }

    /// Where `url`'s art is cached when printed in `duotone` — the plain art's
    /// key when there's none. Pass it to `image(for:)` for a synchronous read.
    func key(_ url: URL, duotone: Duotone?) -> URL {
        guard let duotone else { return url }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.fragment = "duotone-\(duotone.index)"
        return parts?.url ?? url
    }

    /// Download (or read from disk) and decode `url`'s art, keeping it in memory
    /// — printed in `duotone` when given. `nil` on failure; callers fall back to
    /// their placeholder.
    @discardableResult
    func load(_ url: URL, duotone: Duotone? = nil) async -> Image? {
        let key = key(url, duotone: duotone)
        if let hit = image(for: key) { return hit }
        if let inFlight = loading[key] { return await inFlight.value }
        let task = Task { () -> Image? in
            guard let (data, _) = try? await session.data(from: url),
                  let cgImage = await Self.decode(data, duotone: duotone)
            else { return nil }
            let image = Image(decorative: cgImage, scale: 1)
            images.setObject(CachedImage(image), forKey: key as NSURL,
                             cost: cgImage.bytesPerRow * cgImage.height)
            remember(image, for: key)
            return image
        }
        loading[key] = task
        let result = await task.value
        loading[key] = nil
        return result
    }

    /// Warm the dealt start's art so `ChainArt` can draw it at once.
    func warm(_ node: ChainNode) async {
        guard let url = Config.imageURL(path: node.imagePath, size: "w185") else { return }
        await load(url)
    }

    /// Warm several images — each plain or in its duotone — four at a time so a
    /// long list doesn't open dozens of connections at once.
    func warm(_ items: [(url: URL, duotone: Duotone?)]) async {
        for start in stride(from: 0, to: items.count, by: 4) {
            await withTaskGroup(of: Void.self) { group in
                for item in items[start..<min(start + 4, items.count)] {
                    group.addTask { await self.load(item.url, duotone: item.duotone) }
                }
            }
        }
    }

    /// Off-main decode, `@concurrent` for the same reason as `TMDBProvider.decode`:
    /// a plain `nonisolated async` function would run on the caller's actor (Main).
    /// `ShouldCacheImmediately` decodes now, not lazily on first draw — which
    /// would land on the main thread mid-animation. A duotone is applied here
    /// too, so it never costs the main thread anything either.
    @concurrent
    nonisolated private static func decode(_ data: Data, duotone: Duotone?) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
        guard let duotone else { return image }
        return duotone.apply(to: image)
    }
}

/// `NSCache` holds objects; this boxes a decoded image.
private final class CachedImage {
    let image: Image
    init(_ image: Image) { self.image = image }
}
