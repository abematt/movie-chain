//
//  DailyStartFeed.swift
//  movie-quiz
//
//  Where published daily starts come from: the service's `puzzles` table, read
//  straight through its REST API with the publishable key (row-level security
//  lets the public roles read it and nothing else). One small request covers a
//  week, so the phone keeps the days ahead and the daily survives losing signal.
//

import Foundation

/// The published daily starts for a range of day numbers. A day that isn't in the
/// result falls back to `DailyStart.entries`.
protocol DailyStartFeed {
    func dailyStarts(_ numbers: ClosedRange<Int>) async throws -> [Int: DailyStart.Entry]
}

struct ServiceDailyStartFeed: DailyStartFeed {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func dailyStarts(_ numbers: ClosedRange<Int>) async throws -> [Int: DailyStart.Entry] {
        var comps = URLComponents(url: Config.serviceURL.appending(path: "rest/v1/puzzles"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "select", value: "number,revision,data"),
            URLQueryItem(name: "mode", value: "eq.daily_start"),
            URLQueryItem(name: "number", value: "gte.\(numbers.lowerBound)"),
            URLQueryItem(name: "number", value: "lte.\(numbers.upperBound)"),
        ]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = Config.requestTimeout
        req.setValue("application/json", forHTTPHeaderField: "accept")
        req.setValue(Config.serviceKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DataProviderError.badResponse(-1) }
        guard (200...299).contains(http.statusCode) else { throw DataProviderError.badResponse(http.statusCode) }
        return DailyStart.latest(try await Self.decode(data))
    }

    /// Off-main decode; `@concurrent` because a plain `nonisolated async` func
    /// would run on the caller's actor (main).
    @concurrent
    nonisolated private static func decode(_ data: Data) async throws -> [DailyStart.Served] {
        do { return try JSONDecoder().decode([DailyStart.Served].self, from: data) }
        catch { throw DataProviderError.decoding }
    }
}
