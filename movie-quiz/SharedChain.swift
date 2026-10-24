//
//  SharedChain.swift
//  movie-quiz
//
//  Chain sharing: a run as a link, and a link back into a run. Every social
//  feature travels as one of these — the game-over share, a challenge ("beat my
//  start"), a daily result — so there is one format, one version number and one
//  parser, and opening any of them ends in `startGame(with:)`.
//
//  Pure like `FuzzyMatch` and `Scoring`: no UIKit, no network. A link is
//  untrusted input, so `open` checks everything and never throws: it answers
//  with a chain, "this needs a newer Unspool", or "not a chain".
//
//  The wire format is compact JSON in base64url, under `<base>/c?d=…`. It isn't
//  encrypted: anyone who decodes a link before playing can read the route. That's
//  accepted between friends; the app itself only shows the route afterwards.
//

import Foundation

nonisolated struct SharedChain: Equatable, Sendable {
    /// The chain's first node, with its name so a challenge reads instantly
    /// without a lookup ("9 links from Tom Hanks").
    struct Start: Equatable, Sendable {
        var kind: NodeKind
        var id: Int
        var name: String
    }

    /// The wire format's version. Bump it when an old app would misread a new
    /// link; adding a field old apps can ignore doesn't need a bump.
    static let version = 1
    /// Sanity bounds on untrusted input, far above anything a real run reaches.
    static let maxLinks = 500
    static let maxNameLength = 200
    static let maxSenderLength = 40

    var start: Start
    /// TMDB ids of every link after the start, in order. Kinds alternate from the
    /// start's, so they aren't stored.
    var links: [Int]
    var points: Int
    /// Who shared it: a random id made once per device (`SharerID`), never the
    /// device id analytics uses. A future account claims it like the device id.
    var sharer: UUID?
    /// The name the sender goes by, when there is one.
    var senderName: String?

    /// The score: links after the start (the dealt start isn't a link).
    var linkCount: Int { links.count }

    /// A finished run as a shareable chain. `nil` for an empty chain.
    /// `@MainActor` because `ChainNode` is (the project's default isolation).
    @MainActor
    init?(chain: [ChainNode], points: Int, sharer: UUID? = nil, senderName: String? = nil) {
        guard let first = chain.first else { return nil }
        self.init(start: Start(kind: first.kind, id: first.tmdbID, name: first.matchText),
                  links: chain.dropFirst().map(\.tmdbID),
                  points: points, sharer: sharer, senderName: senderName)
    }

    init(start: Start, links: [Int], points: Int, sharer: UUID? = nil, senderName: String? = nil) {
        self.start = start
        self.links = links
        self.points = points
        self.sharer = sharer
        self.senderName = senderName
    }

    /// The node to start a run from — what a challenge plays.
    @MainActor
    var startNode: ChainNode {
        switch start.kind {
        case .actor: .actor(Person(id: start.id, name: start.name))
        case .movie: .movie(Movie(id: start.id, title: start.name, year: nil))
        }
    }

    // MARK: Link

    /// `<base>/c?d=<payload>`.
    func url(base: URL) -> URL {
        base.appending(path: "c").appending(queryItems: [URLQueryItem(name: "d", value: encoded)])
    }

    enum Opened: Equatable {
        case chain(SharedChain)
        /// A link from a newer app, in a format this one can't read.
        case needsUpdate
        /// Not a chain link, or a damaged one.
        case invalid
    }

    /// Read a link. Only `<base>/c?d=…` on the base's own host is a chain.
    static func open(_ url: URL, base: URL) -> Opened {
        guard let host = url.host(), host.lowercased() == base.host()?.lowercased(),
              url.path() == "/c" || url.path() == "/c/",
              let payload = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "d" })?.value,
              let data = Data(base64URL: payload)
        else { return .invalid }

        // The version first, on its own, so a newer format with a different shape
        // still reads as "update" rather than "invalid".
        guard let version = try? JSONDecoder().decode(VersionOnly.self, from: data).v
        else { return .invalid }
        guard version <= Self.version else { return .needsUpdate }
        guard version >= 1, let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let chain = wire.chain
        else { return .invalid }
        return .chain(chain)
    }

    // MARK: Wire format

    private var encoded: String {
        let wire = Wire(v: Self.version, k: start.kind == .actor ? "a" : "m", s: start.id,
                        n: start.name, l: links, p: points,
                        u: sharer?.uuidString, f: senderName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Encoding a struct of strings and ints can't fail.
        let data = (try? encoder.encode(wire)) ?? Data()
        return data.base64URLEncodedString()
    }

    private struct VersionOnly: Decodable { var v: Int }

    /// Short keys keep the link short: version, kind, start id, name, links,
    /// points, sharer, from.
    private struct Wire: Codable {
        var v: Int
        var k: String
        var s: Int
        var n: String
        var l: [Int]
        var p: Int
        var u: String?
        var f: String?

        /// The checked chain, or `nil` if anything is out of bounds.
        var chain: SharedChain? {
            let kind: NodeKind
            switch k {
            case "a": kind = .actor
            case "m": kind = .movie
            default: return nil
            }
            let name = n.trimmingCharacters(in: .whitespacesAndNewlines)
            guard s > 0, !name.isEmpty, name.count <= SharedChain.maxNameLength,
                  l.count <= SharedChain.maxLinks, l.allSatisfy({ $0 > 0 }),
                  p >= 0
            else { return nil }
            let sender = f.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(SharedChain.maxSenderLength)) }
            return SharedChain(start: Start(kind: kind, id: s, name: name), links: l, points: p,
                               sharer: u.flatMap(UUID.init(uuidString:)),
                               senderName: sender?.isEmpty == false ? sender : nil)
        }
    }
}

// MARK: - Sharer id

/// A random id made the first time this device shares, kept here and sent in
/// links. Separate from `DeviceID` on purpose: that one is the anonymous id in
/// analytics, and a link anyone can read shouldn't carry it.
enum SharerID {
    static let key = "sharerID"

    static func current(in defaults: UserDefaults) -> UUID {
        if let stored = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) {
            return stored
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}

// MARK: - base64url

nonisolated extension Data {
    /// Base64 with the URL-safe alphabet and no padding (RFC 4648 §5).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
