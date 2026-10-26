//
//  RunResultsTests.swift
//  movie-quizTests
//
//  Finished runs for the service's `results`: what's sent (ids and times, the
//  shape the Edge Function checks), and the outbox that holds a run until it's
//  delivered.
//

import Foundation
import Testing
@testable import movie_quiz

@MainActor
struct RunResultsTests {

    private let device = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    private static func actor(_ id: Int) -> ChainNode { .actor(Person(id: id, name: "A\(id)")) }
    private static func movie(_ id: Int) -> ChainNode { .movie(Movie(id: id, title: "M\(id)", year: 2000)) }

    private static func turn(_ prompt: ChainNode, _ answer: ChainNode, ms: Int) -> GameEngine.Turn {
        GameEngine.Turn(prompt: prompt, answer: answer, typed: "secret typing", misses: ["a miss"],
                        answerTime: .milliseconds(ms), loadTime: .zero)
    }

    private static let run: GameEngine.Summary = {
        let chain = [actor(31), movie(13), actor(500)]
        return GameEngine.Summary(chain: chain, links: 2, points: 61, endedByQuit: true,
                                  turns: [turn(chain[0], chain[1], ms: 4_240), turn(chain[1], chain[2], ms: 12_960)])
    }()

    // MARK: The payload

    @Test func aRunIsItsIdsAndTimes() {
        let result = RunResult(summary: Self.run, deviceID: device, appVersion: "0.7.0")
        #expect(result.mode == "endless")
        #expect(result.number == nil)
        #expect(result.chain == [
            .init(kind: .actor, id: 31, seconds: nil),
            .init(kind: .movie, id: 13, seconds: 4.2),
            .init(kind: .actor, id: 500, seconds: 13.0),
        ])
        #expect(result.links == 2)
        #expect(result.points == 61)
        #expect(result.endedByQuit)
    }

    @Test func aDailyCarriesItsNumber() {
        var daily = Self.run
        daily.daily = 4
        let result = RunResult(summary: daily, deviceID: device, appVersion: "0.7.0")
        #expect(result.mode == "daily_start")
        #expect(result.number == 4)
    }

    /// The keys the Edge Function reads, `number` as an explicit null, and no
    /// typed text anywhere.
    @Test func theJSONIsWhatTheServiceTakes() throws {
        let data = try JSONEncoder().encode(RunResult(summary: Self.run, deviceID: device, appVersion: "0.7.0"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["device_id", "mode", "number", "chain", "links", "points",
                                   "ended_by_quit", "app_version"])
        #expect(json["number"] is NSNull)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("secret typing"))
        #expect(!text.contains("a miss"))
    }

    @Test(arguments: [
        (201, ResultsOutbox.Delivery.delivered), (200, .delivered),
        (422, .rejected), (413, .rejected),
        (401, .failed), (429, .failed), (500, .failed), (503, .failed),
    ])
    func statusesMapToDeliveries(_ status: Int, _ expected: ResultsOutbox.Delivery) {
        #expect(ServiceResultsTransport.delivery(status: status) == expected)
    }

    // MARK: The outbox

    /// Answers each send from a script, recording what was sent.
    final class Service {
        var answers: [ResultsOutbox.Delivery]
        private(set) var sent: [RunResult] = []
        init(_ answers: [ResultsOutbox.Delivery]) { self.answers = answers }
        func send(_ result: RunResult) async -> ResultsOutbox.Delivery {
            sent.append(result)
            return answers.isEmpty ? .delivered : answers.removeFirst()
        }
    }

    private func makeOutbox(_ service: Service, defaults: UserDefaults) -> ResultsOutbox {
        ResultsOutbox(defaults: defaults, deviceID: device, appVersion: "0.7.0", send: service.send)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "RunResultsTests-\(UUID().uuidString)")!
    }

    @Test func aDeliveredRunLeavesTheOutbox() async {
        let service = Service([.delivered])
        let outbox = makeOutbox(service, defaults: freshDefaults())
        outbox.record(Self.run)
        await outbox.flush()
        #expect(service.sent.count == 1)
        #expect(outbox.pending.isEmpty)
    }

    @Test func aFailedSendIsKeptAndSentNextTime() async {
        let defaults = freshDefaults()
        let offline = Service([.failed, .failed])
        let outbox = makeOutbox(offline, defaults: defaults)
        outbox.record(Self.run)
        await outbox.flush()
        #expect(outbox.pending.count == 1)

        // A relaunch with signal delivers it.
        let online = Service([])
        let relaunched = makeOutbox(online, defaults: defaults)
        #expect(relaunched.pending.count == 1)
        await relaunched.flush()
        #expect(online.sent.count == 1)
        #expect(relaunched.pending.isEmpty)
    }

    @Test func aRejectedRunIsDropped() async {
        let service = Service([.rejected])
        let outbox = makeOutbox(service, defaults: freshDefaults())
        outbox.record(Self.run)
        await outbox.flush()
        #expect(outbox.pending.isEmpty)
    }

    @Test func theOutboxKeepsOnlyTheNewestRuns() async {
        let service = Service(Array(repeating: .failed, count: 200))
        let outbox = makeOutbox(service, defaults: freshDefaults())
        for points in 0..<(ResultsOutbox.limit + 5) {
            var run = Self.run
            run.points = points
            outbox.record(run)
        }
        await outbox.flush()
        #expect(outbox.pending.count == ResultsOutbox.limit)
        #expect(outbox.pending.first?.points == 5)
    }

    // MARK: The engine

    @Test func everyGameOverIsRecorded() async {
        let service = Service([])
        let outbox = makeOutbox(service, defaults: freshDefaults())
        let engine = GameEngine(provider: StubProvider(), defaults: freshDefaults(), results: outbox)
        await engine.startGame(with: Self.actor(31))
        engine.quit()
        await outbox.flush()
        #expect(service.sent.count == 1)
        #expect(service.sent.first?.chain.first?.id == 31)
        #expect(service.sent.first?.links == 0)
    }
}
