//
//  RunResults.swift
//  movie-quiz
//
//  Every finished run goes to the service's `results` table, for per-day stats
//  and the answer data (which actors and films players actually name). Not
//  analytics: that's PostHog, and stays there (docs/ANALYTICS.md). A run belongs
//  to the player the service reads from the session token (`PlayerSession`),
//  never to an id in the body, and carries TMDB ids, never typed text.
//
//  The outbox keeps a run until the service has it, so a game over without
//  signal is delivered on a later visit home.
//

import Foundation

/// A finished run as the `results` Edge Function takes it.
nonisolated struct RunResult: Codable, Equatable, Sendable {
    struct Link: Codable, Equatable, Sendable {
        var kind: NodeKind
        var id: Int
        /// Clock time the link took; `nil` on the start.
        var seconds: Double?
    }

    /// `daily_start` for a daily, else `endless`.
    var mode: String
    var number: Int?
    var chain: [Link]
    var links: Int
    var points: Int
    var endedByQuit: Bool
    var appVersion: String

    private enum CodingKeys: String, CodingKey {
        case mode, number, chain, links, points
        case endedByQuit = "ended_by_quit", appVersion = "app_version"
    }

    // `number` is sent as null on an endless run, not left out.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(number, forKey: .number)
        try c.encode(chain, forKey: .chain)
        try c.encode(links, forKey: .links)
        try c.encode(points, forKey: .points)
        try c.encode(endedByQuit, forKey: .endedByQuit)
        try c.encode(appVersion, forKey: .appVersion)
    }
}

extension RunResult {
    /// The run in `summary`: the start, then each link with the time it took.
    init(summary: GameEngine.Summary, appVersion: String) {
        let seconds = summary.turns.map { turn in
            let parts = turn.answerTime.components
            return ((Double(parts.seconds) + Double(parts.attoseconds) / 1e18) * 10).rounded() / 10
        }
        self.init(
            mode: summary.daily == nil ? "endless" : "daily_start",
            number: summary.daily,
            chain: summary.chain.enumerated().map { i, node in
                Link(kind: node.kind, id: node.tmdbID, seconds: i > 0 && i <= seconds.count ? seconds[i - 1] : nil)
            },
            links: summary.links,
            points: summary.points,
            endedByQuit: summary.endedByQuit,
            appVersion: appVersion
        )
    }
}

/// Holds finished runs until the service has them.
final class ResultsOutbox {
    /// What came of one send.
    enum Delivery: Sendable {
        /// Stored, or already stored.
        case delivered
        /// The service refused the run as invalid; resending won't help.
        case rejected
        /// No answer, or a fault on the way; try again later.
        case failed
    }

    /// Runs kept beyond this drop the oldest, so a long time offline can't grow
    /// the store without bound.
    static let limit = 50
    private static let key = "pendingResults"

    private let defaults: UserDefaults
    private let appVersion: String
    private let send: (RunResult) async -> Delivery
    private(set) var pending: [RunResult]
    private var flushing: Task<Void, Never>?

    /// Runs saved by earlier versions carried a `device_id`; it's ignored on
    /// decode, and the service takes the player from the token instead.
    init(defaults: UserDefaults, appVersion: String,
         send: @escaping (RunResult) async -> Delivery) {
        self.defaults = defaults
        self.appVersion = appVersion
        self.send = send
        self.pending = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([RunResult].self, from: $0) } ?? []
    }

    /// Keep the run and try to deliver everything waiting.
    func record(_ summary: GameEngine.Summary) {
        pending.append(RunResult(summary: summary, appVersion: appVersion))
        if pending.count > Self.limit { pending.removeFirst(pending.count - Self.limit) }
        save()
        Task { await flush() }
    }

    /// Deliver waiting runs in order, stopping at the first that fails to send.
    /// A flush already running is joined, so no run is sent twice at once.
    func flush() async {
        if let flushing {
            await flushing.value
            return
        }
        let task = Task {
            while let next = pending.first {
                if await send(next) == .failed { break }
                pending.removeFirst()
                save()
            }
        }
        flushing = task
        await task.value
        flushing = nil
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(pending), forKey: Self.key)
    }
}

/// Posts a run to the service's `results` function, as the session's player.
struct ServiceResultsTransport {
    /// A token for the player; `true` asks for a fresh one after a 401.
    typealias Token = (_ forceRefresh: Bool) async -> String?
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport
    private let token: Token

    init(token: @escaping Token,
         transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.token = token
        self.transport = transport
    }

    func send(_ result: RunResult) async -> ResultsOutbox.Delivery {
        guard let body = try? JSONEncoder().encode(result) else { return .rejected }
        // A token can expire between being handed out and arriving: one retry.
        for attempt in 0..<2 {
            guard let bearer = await token(attempt > 0) else { return .failed }
            var req = URLRequest(url: Config.serviceURL.appending(path: "functions/v1/results"))
            req.httpMethod = "POST"
            req.timeoutInterval = Config.requestTimeout
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(Config.serviceKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            req.httpBody = body
            guard let (_, response) = try? await transport(req),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else { return .failed }
            if status != 401 { return Self.delivery(status: status) }
        }
        return .failed
    }

    /// 2xx is delivered. A 4xx means the run itself was refused — except the
    /// ones that are about the moment (wrong key or token, timeout, too many requests).
    static func delivery(status: Int) -> ResultsOutbox.Delivery {
        switch status {
        case 200..<300: .delivered
        case 401, 408, 429: .failed
        case 400..<500: .rejected
        default: .failed
        }
    }
}
