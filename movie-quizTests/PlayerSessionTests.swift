//
//  PlayerSessionTests.swift
//  movie-quizTests
//
//  The anonymous service player: made once, refreshed before it expires, joined
//  rather than renewed twice, replaced only when the service refuses it, and its
//  id kept among this install's ids so old challenges stay yours.
//

import Foundation
import Testing
@testable import movie_quiz

@MainActor
struct PlayerSessionTests {

    /// Answers each request from a script, recording what was asked.
    final class Service {
        enum Reply { case token(user: UUID, access: String, refresh: String, expiresIn: Double = 3600)
                     case status(Int), offline }
        var replies: [Reply]
        private(set) var requests: [URLRequest] = []
        init(_ replies: [Reply]) { self.replies = replies }

        func handle(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            await Task.yield()      // let a second caller arrive mid-request
            let reply = replies.isEmpty ? .status(500) : replies.removeFirst()
            let url = request.url!
            switch reply {
            case .offline:
                throw URLError(.notConnectedToInternet)
            case .status(let code):
                return (Data(), HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
            case .token(let user, let access, let refresh, let expiresIn):
                let body = """
                {"access_token":"\(access)","refresh_token":"\(refresh)","expires_in":\(expiresIn),\
                "token_type":"bearer","user":{"id":"\(user.uuidString.lowercased())","is_anonymous":true}}
                """
                return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }

        var paths: [String] { requests.map { $0.url!.path() } }
    }

    final class MemoryVault: SessionVault {
        var stored: ServiceSession?
        init(_ stored: ServiceSession? = nil) { self.stored = stored }
        func load() -> ServiceSession? { stored }
        func save(_ session: ServiceSession?) { stored = session }
    }

    private let alice = UUID(uuidString: "A11CE000-0000-4000-8000-000000000001")!
    private let bob = UUID(uuidString: "B0B00000-0000-4000-8000-000000000002")!
    private let defaults = UserDefaults(suiteName: "PlayerSessionTests-\(UUID().uuidString)")!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeSession(_ service: Service, vault: MemoryVault = MemoryVault()) -> PlayerSession {
        let now = clock
        return PlayerSession(vault: vault, defaults: defaults, baseURL: URL(string: "https://unspool.test")!,
                             key: "sb_publishable_test", now: { now }, transport: service.handle)
    }

    @Test func theFirstCallSignsInAnonymouslyAndKeepsTheSession() async {
        let service = Service([.token(user: alice, access: "a1", refresh: "r1")])
        let vault = MemoryVault()
        let session = makeSession(service, vault: vault)

        #expect(await session.accessToken() == "a1")
        #expect(service.paths == ["/auth/v1/signup"])
        #expect(service.requests[0].value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
        #expect(vault.stored?.userID == alice)
        #expect(PlayerID.current(in: defaults) == alice)

        // Fresh, so it's reused without a request.
        #expect(await session.accessToken() == "a1")
        #expect(service.requests.count == 1)
    }

    @Test func aRelaunchIsTheSamePlayer() async {
        let vault = MemoryVault(ServiceSession(userID: alice, accessToken: "a1", refreshToken: "r1",
                                               expiresAt: clock.addingTimeInterval(3600)))
        let service = Service([])
        let session = makeSession(service, vault: vault)
        #expect(session.userID == alice)
        #expect(PlayerID.current(in: defaults) == alice, "a reinstall restores the id from the Keychain")
        #expect(await session.accessToken() == "a1")
        #expect(service.requests.isEmpty)
    }

    @Test func aTokenNearExpiryIsRefreshedNotReplaced() async throws {
        let vault = MemoryVault(ServiceSession(userID: alice, accessToken: "a1", refreshToken: "r1",
                                               expiresAt: clock.addingTimeInterval(30)))
        let service = Service([.token(user: alice, access: "a2", refresh: "r2")])
        let session = makeSession(service, vault: vault)

        #expect(await session.accessToken() == "a2")
        let request = try #require(service.requests.first)
        #expect(request.url?.path() == "/auth/v1/token")
        #expect(request.url?.query()?.contains("grant_type=refresh_token") == true)
        let body = try #require(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body["refresh_token"] == "r1")
        #expect(vault.stored?.refreshToken == "r2")
        #expect(session.userID == alice)
    }

    @Test func offlineGivesNoTokenAndKeepsTheSession() async {
        let vault = MemoryVault(ServiceSession(userID: alice, accessToken: "a1", refreshToken: "r1",
                                               expiresAt: clock.addingTimeInterval(-10)))
        let session = makeSession(Service([.offline]), vault: vault)
        #expect(await session.accessToken() == nil)
        #expect(vault.stored?.userID == alice, "a failed refresh never discards the player")
    }

    @Test func aRateLimitIsTheMomentNotAVerdict() async {
        let vault = MemoryVault(ServiceSession(userID: alice, accessToken: "a1", refreshToken: "r1",
                                               expiresAt: clock.addingTimeInterval(-10)))
        let service = Service([.status(429)])
        let session = makeSession(service, vault: vault)
        #expect(await session.accessToken() == nil)
        #expect(service.paths == ["/auth/v1/token"], "no new player for a busy service")
        #expect(session.userID == alice)
    }

    @Test func aRefusedRefreshStartsANewPlayerAndOldChallengesStayYours() async {
        let vault = MemoryVault(ServiceSession(userID: alice, accessToken: "a1", refreshToken: "r1",
                                               expiresAt: clock.addingTimeInterval(-10)))
        let service = Service([.status(400), .token(user: bob, access: "b1", refresh: "rb")])
        let session = makeSession(service, vault: vault)

        #expect(await session.accessToken() == "b1")
        #expect(service.paths == ["/auth/v1/token", "/auth/v1/signup"])
        #expect(PlayerID.current(in: defaults) == bob)
        #expect(PlayerID.all(in: defaults).isSuperset(of: [alice, bob]))
    }

    @Test func concurrentCallersShareOneSignIn() async {
        let service = Service([.token(user: alice, access: "a1", refresh: "r1"),
                               .token(user: bob, access: "b1", refresh: "rb")])
        let session = makeSession(service)
        async let first = session.accessToken()
        async let second = session.accessToken()
        let tokens = await [first, second]
        #expect(tokens == ["a1", "a1"])
        #expect(service.requests.count == 1, "a second sign-in would make a second player")
    }

    @Test func theLocalIDCountsAsYoursAfterTheServiceAssignsOne() {
        let local = SharerID.current(in: defaults)
        #expect(PlayerID.current(in: defaults) == local, "before the service, links use the local id")
        PlayerID.adopt(alice, in: defaults)
        #expect(PlayerID.current(in: defaults) == alice)
        #expect(PlayerID.all(in: defaults) == [local, alice])
    }

    // MARK: Profile

    @Test func aNameIsWrittenOnceToYourOwnProfile() async throws {
        let service = Service([.token(user: alice, access: "a1", refresh: "r1"), .status(201)])
        let session = makeSession(service)

        await session.syncProfile(name: "Abe")
        #expect(service.paths == ["/auth/v1/signup", "/rest/v1/profiles"])
        let write = service.requests[1]
        #expect(write.value(forHTTPHeaderField: "Authorization") == "Bearer a1")
        #expect(write.value(forHTTPHeaderField: "Prefer")?.contains("resolution=merge-duplicates") == true)
        let body = try #require(write.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body == ["id": alice.uuidString.lowercased(), "display_name": "Abe"])

        await session.syncProfile(name: "Abe")
        #expect(service.requests.count == 2, "an unchanged name isn't resent")
        await session.syncProfile(name: nil)
        #expect(service.requests.count == 2, "no name writes nothing")
    }

    @Test func aFailedProfileWriteIsRetriedNextTime() async {
        let service = Service([.token(user: alice, access: "a1", refresh: "r1"), .offline, .status(201)])
        let session = makeSession(service)
        await session.syncProfile(name: "Abe")
        await session.syncProfile(name: "Abe")
        #expect(service.paths.filter { $0 == "/rest/v1/profiles" }.count == 2)
        #expect(defaults.string(forKey: PlayerSession.syncedNameKey) == "Abe")
    }
}
