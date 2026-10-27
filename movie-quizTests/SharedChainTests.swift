//
//  SharedChainTests.swift
//  movie-quizTests
//
//  Chain sharing's link format: a run survives the trip into a link and back,
//  and anything that isn't a well-formed link from this app — another host, a
//  damaged payload, out-of-bounds values — is refused rather than half-read. A
//  link from a newer app asks for an update instead.
//

import Foundation
import Testing
@testable import movie_quiz

@MainActor
struct SharedChainTests {

    private let base = URL(string: "https://unspool.example")!
    private let sharer = UUID()

    private let hanks = Person(id: 31, name: "Tom Hanks")
    private let castAway = Movie(id: 8358, title: "Cast Away", year: 2000)
    private let hunt = Person(id: 7, name: "Helen Hunt")

    private var run: [ChainNode] { [.actor(hanks), .movie(castAway), .actor(hunt)] }

    /// A link carrying exactly this JSON, to test what the parser does with
    /// payloads the app would never write.
    private func link(json: String, path: String = "/c", host: String = "unspool.example") -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [URLQueryItem(name: "d", value: Data(json.utf8).base64URLEncodedString())]
        return components.url!
    }

    // MARK: Round trip

    @Test func aRunSurvivesTheTripThroughALink() throws {
        let shared = try #require(SharedChain(chain: run, points: 420, sharer: sharer, senderName: "Abe"))
        let url = shared.url(base: base)

        #expect(url.absoluteString.hasPrefix("https://unspool.example/c?d="))
        #expect(SharedChain.open(url, base: base) == .chain(shared))
        #expect(shared.start == .init(kind: .actor, id: 31, name: "Tom Hanks"))
        #expect(shared.links == [8358, 7])
        #expect(shared.linkCount == 2)
    }

    @Test func aMovieStartKeepsItsTitleWithoutTheYear() throws {
        let shared = try #require(SharedChain(chain: [.movie(castAway)], points: 0))
        #expect(shared.start == .init(kind: .movie, id: 8358, name: "Cast Away"))
        #expect(shared.linkCount == 0)
        #expect(SharedChain.open(shared.url(base: base), base: base) == .chain(shared))
    }

    @Test func theStartIsPlayable() throws {
        let shared = try #require(SharedChain(chain: run, points: 0))
        #expect(shared.startNode == .actor(hanks))   // nodes compare by TMDB id
        #expect(shared.startNode.matchText == "Tom Hanks")
    }

    @Test func anEmptyChainIsNothingToShare() {
        #expect(SharedChain(chain: [], points: 0) == nil)
    }

    @Test func aLongRunStaysAReasonableLink() throws {
        let long: [ChainNode] = (0..<40).map {
            $0.isMultiple(of: 2) ? .actor(Person(id: 100_000 + $0, name: "Actor"))
                                 : .movie(Movie(id: 900_000 + $0, title: "Movie", year: nil))
        }
        let shared = try #require(SharedChain(chain: long, points: 9_999, sharer: sharer))
        #expect(shared.url(base: base).absoluteString.count < 800)
    }

    // MARK: Refusals

    @Test func otherHostsAndPathsAreNotChains() throws {
        let shared = try #require(SharedChain(chain: run, points: 1))
        let url = shared.url(base: base)
        #expect(SharedChain.open(url, base: URL(string: "https://elsewhere.example")!) == .invalid)
        #expect(SharedChain.open(URL(string: "https://unspool.example/about")!, base: base) == .invalid)
        #expect(SharedChain.open(URL(string: "https://unspool.example/c")!, base: base) == .invalid)
    }

    @Test(arguments: [
        "not json",
        #"{"v":1}"#,                                             // missing fields
        #"{"v":1,"k":"x","s":31,"n":"Tom","l":[],"p":0}"#,      // unknown kind
        #"{"v":1,"k":"a","s":0,"n":"Tom","l":[],"p":0}"#,       // no start id
        #"{"v":1,"k":"a","s":31,"n":"  ","l":[],"p":0}"#,       // blank name
        #"{"v":1,"k":"a","s":31,"n":"Tom","l":[5,-1],"p":0}"#,  // bad link id
        #"{"v":1,"k":"a","s":31,"n":"Tom","l":[],"p":-3}"#,     // negative points
        #"{"v":0,"k":"a","s":31,"n":"Tom","l":[],"p":0}"#,      // before version 1
    ])
    func aDamagedPayloadIsRefused(json: String) {
        #expect(SharedChain.open(link(json: json), base: base) == .invalid)
    }

    @Test func tooManyLinksOrTooLongANameIsRefused() {
        let links = (1...(SharedChain.maxLinks + 1)).map(String.init).joined(separator: ",")
        #expect(SharedChain.open(link(json: #"{"v":1,"k":"a","s":31,"n":"Tom","l":[\#(links)],"p":0}"#),
                                 base: base) == .invalid)
        let name = String(repeating: "a", count: SharedChain.maxNameLength + 1)
        #expect(SharedChain.open(link(json: #"{"v":1,"k":"a","s":31,"n":"\#(name)","l":[],"p":0}"#),
                                 base: base) == .invalid)
    }

    @Test func aNewerFormatAsksForAnUpdate() {
        // Whatever shape a future version takes, its version number is read first.
        let json = #"{"v":\#(SharedChain.version + 1),"something":"new"}"#
        #expect(SharedChain.open(link(json: json), base: base) == .needsUpdate)
    }

    @Test func theSenderNameIsTrimmedAndCapped() throws {
        let long = String(repeating: "x", count: 100)
        let opened = SharedChain.open(link(json: #"{"v":1,"k":"a","s":31,"n":"Tom","l":[],"p":0,"f":"  \#(long)  "}"#),
                                      base: base)
        guard case .chain(let chain) = opened else { Issue.record("expected a chain"); return }
        #expect(chain.senderName?.count == SharedChain.maxSenderLength)

        let blank = SharedChain.open(link(json: #"{"v":1,"k":"a","s":31,"n":"Tom","l":[],"p":0,"f":"   "}"#),
                                     base: base)
        guard case .chain(let unnamed) = blank else { Issue.record("expected a chain"); return }
        #expect(unnamed.senderName == nil)
    }

    @Test func unknownFieldsFromALaterSameVersionAppAreIgnored() {
        let opened = SharedChain.open(link(json: #"{"v":1,"k":"m","s":8358,"n":"Cast Away","l":[31],"p":5,"z":true}"#),
                                      base: base)
        #expect(opened == .chain(SharedChain(start: .init(kind: .movie, id: 8358, name: "Cast Away"),
                                             links: [31], points: 5)))
    }

    // MARK: Pieces

    @Test(arguments: ["", "f", "fo", "foo", "foob", "\u{00FF}\u{00FE}\u{00FD}"])
    func base64URLRoundTrips(text: String) throws {
        let data = Data(text.utf8)
        let encoded = data.base64URLEncodedString()
        #expect(!encoded.contains("+") && !encoded.contains("/") && !encoded.contains("="))
        #expect(Data(base64URL: encoded) == data)
    }

    @Test func theSharerIDIsMadeOnceAndIsNotTheDeviceID() throws {
        let defaults = try #require(UserDefaults(suiteName: "SharedChainTests-\(UUID())"))
        let first = SharerID.current(in: defaults)
        #expect(SharerID.current(in: defaults) == first)
        #expect(DeviceID.current(in: defaults) != first)
    }

    // MARK: Replies

    @Test func aReplyCarriesTheRunItAnswers() throws {
        let original = try #require(SharedChain(chain: run, points: 420, sharer: sharer, senderName: "Abe"))
        let replier = UUID()
        let reply = try #require(SharedChain(chain: run + [.movie(Movie(id: 13, title: "Big", year: 1988))],
                                             points: 500, sharer: replier, senderName: "Sam",
                                             replyTo: original.asOriginal))

        #expect(SharedChain.open(reply.url(base: base), base: base) == .chain(reply))
        #expect(reply.replyTo == .init(links: [8358, 7], points: 420, sharer: sharer, senderName: "Abe"))
        #expect(reply.originalChallenge == original)
        #expect(reply.originalChallenge?.challengeKey == original.challengeKey)
    }

    @Test func aDamagedReplySpoilsTheLink() {
        let json = #"{"v":1,"k":"a","s":31,"n":"Tom Hanks","l":[8358],"p":10,"u":"\#(UUID().uuidString)","r":{"l":[8358],"p":5,"u":"not-a-uuid"}}"#
        #expect(SharedChain.open(link(json: json), base: base) == .invalid)
    }

    @Test func aChallengeIsNamedBySenderStartAndRun() throws {
        let one = try #require(SharedChain(chain: run, points: 420, sharer: sharer))
        let samePointsAside = try #require(SharedChain(chain: run, points: 1, sharer: sharer, senderName: "New name"))
        let otherSender = try #require(SharedChain(chain: run, points: 420, sharer: UUID()))
        let otherRun = try #require(SharedChain(chain: Array(run.prefix(2)), points: 420, sharer: sharer))

        #expect(one.challengeKey == samePointsAside.challengeKey)
        #expect(one.challengeKey != otherSender.challengeKey)
        #expect(one.challengeKey != otherRun.challengeKey)
        #expect(SharedChain(start: one.start, links: one.links, points: 0).asOriginal == nil,
                "a reply needs someone to go back to")
    }
}
