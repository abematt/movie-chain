//
//  PlayerSession.swift
//  movie-quiz
//
//  Who this install is to Unspool's service: an anonymous Supabase user, made
//  silently the first time it's needed. Its id is the player id everywhere, in
//  challenge links, on results, on the profile and on analytics events; signing
//  in at 0.9.0 links Apple, Google or email to this same user, so nothing moves.
//
//  The session (tokens included) lives in the Keychain, which outlives a
//  reinstall, so a reinstalled phone is still the same player. The id alone is
//  mirrored into UserDefaults (`PlayerID`) for the synchronous reads views make.
//

import Foundation
import Security

/// A signed-in session as Supabase Auth returns it.
nonisolated struct ServiceSession: Codable, Equatable, Sendable {
    var userID: UUID
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Where the session is kept. The Keychain in the app; memory in tests.
protocol SessionVault {
    func load() -> ServiceSession?
    func save(_ session: ServiceSession?)
}

/// The anonymous player behind every service call.
final class PlayerSession {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    /// A token this close to expiry is refreshed before use.
    static let refreshMargin: TimeInterval = 60

    private(set) var current: ServiceSession?
    var userID: UUID? { current?.userID }

    private let vault: any SessionVault
    private let defaults: UserDefaults
    private let baseURL: URL
    private let key: String
    private let now: () -> Date
    private let transport: Transport
    /// One sign-in or refresh at a time: a second caller joins it, so a refresh
    /// token is never spent twice (rotation would revoke the session).
    private var inFlight: Task<ServiceSession?, Never>?

    init(vault: any SessionVault, defaults: UserDefaults, baseURL: URL = Config.serviceURL,
         key: String = Config.serviceKey, now: @escaping () -> Date = Date.init,
         transport: @escaping Transport) {
        self.vault = vault
        self.defaults = defaults
        self.baseURL = baseURL
        self.key = key
        self.now = now
        self.transport = transport
        current = vault.load()
        if let current { PlayerID.adopt(current.userID, in: defaults) }
    }

    /// The live session for the app, or `nil` where nothing should reach the
    /// service as a player: no service key, the test host, previews.
    static func live() -> PlayerSession? {
        let env = ProcessInfo.processInfo.environment
        guard Config.hasService,
              env["XCTestConfigurationFilePath"] == nil,
              env["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
        else { return nil }
        return PlayerSession(vault: KeychainSessionVault(), defaults: .standard) { request in
            try await URLSession.shared.data(for: request)
        }
    }

    /// A token to call the service with, signing in or refreshing first when
    /// needed; `nil` when the service can't be reached. `forceRefresh` after the
    /// service refused the token it was given.
    func accessToken(forceRefresh: Bool = false) async -> String? {
        if let inFlight { return await inFlight.value?.accessToken }
        if let current, !forceRefresh, current.expiresAt.timeIntervalSince(now()) > Self.refreshMargin {
            return current.accessToken
        }
        let task = Task { await renew() }
        inFlight = task
        let session = await task.value
        inFlight = nil
        return session?.accessToken
    }

    /// Refresh the session, or make one. A refresh the service rejects outright
    /// means the session is gone (revoked, or the user deleted); a new anonymous
    /// user takes over, and `PlayerID` keeps the old id as one of yours.
    private func renew() async -> ServiceSession? {
        if let current {
            switch await call("token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                              body: ["refresh_token": current.refreshToken]) {
            case .session(let fresh): return store(fresh)
            case .unreachable: return nil
            case .refused: break
            }
        }
        switch await call("signup", body: [:]) {
        case .session(let fresh): return store(fresh)
        case .unreachable, .refused: return nil
        }
    }

    private func store(_ session: ServiceSession) -> ServiceSession {
        current = session
        vault.save(session)
        PlayerID.adopt(session.userID, in: defaults)
        return session
    }

    // MARK: Auth API

    private enum Answer { case session(ServiceSession), refused, unreachable }

    /// The fields of Supabase Auth's token response this needs.
    private nonisolated struct TokenResponse: Decodable {
        struct User: Decodable { let id: UUID }
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User
    }

    private func call(_ path: String, query: [URLQueryItem] = [], body: [String: String]) async -> Answer {
        var components = URLComponents(url: baseURL.appending(path: "auth/v1/\(path)"),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = Config.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONEncoder().encode(body)
        let started = now()
        guard let (data, response) = try? await transport(request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return .unreachable }
        // 4xx other than a rate limit is a verdict on the request; the rest is the moment.
        guard (200..<300).contains(status) else {
            return (400..<500).contains(status) && status != 408 && status != 429 ? .refused : .unreachable
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else { return .unreachable }
        return .session(ServiceSession(userID: token.user.id, accessToken: token.access_token,
                                       refreshToken: token.refresh_token,
                                       expiresAt: started.addingTimeInterval(token.expires_in)))
    }

    // MARK: Profile

    /// The name last written to the profile, so an unchanged name isn't resent.
    static let syncedNameKey = "profileSyncedName"

    /// Write the display name to this player's `profiles` row when it changed
    /// since the last write. An empty name writes nothing (the row keeps the old one).
    func syncProfile(name: String?) async {
        guard let name, name != defaults.string(forKey: Self.syncedNameKey) else { return }
        for attempt in 0..<2 {
            guard let token = await accessToken(forceRefresh: attempt > 0) else { return }
            var request = URLRequest(url: baseURL.appending(path: "rest/v1/profiles")
                .appending(queryItems: [URLQueryItem(name: "on_conflict", value: "id")]))
            request.httpMethod = "POST"
            request.timeoutInterval = Config.requestTimeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            // The row's id is the caller's own (a default of auth.uid()); sending
            // it would make the upsert update `id`, which players can't.
            request.httpBody = try? JSONEncoder().encode(["display_name": name])
            guard let (_, response) = try? await transport(request),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else { return }
            if (200..<300).contains(status) {
                defaults.set(name, forKey: Self.syncedNameKey)
                return
            }
            if status != 401 { return }
        }
    }
}

// MARK: - Player id

/// The id this install goes by, readable synchronously: the service user once
/// there is one, else the local id made before it (`SharerID`, which a phone
/// that hasn't reached the service yet still shares under).
enum PlayerID {
    static let key = "playerID"
    /// Every id this install has gone by, so a reply to a challenge sent under
    /// any of them is still recognised as yours.
    static let allKey = "playerIDs"

    static func current(in defaults: UserDefaults) -> UUID {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? SharerID.current(in: defaults)
    }

    static func all(in defaults: UserDefaults) -> Set<UUID> {
        var ids = Set((defaults.stringArray(forKey: allKey) ?? []).compactMap(UUID.init(uuidString:)))
        ids.insert(current(in: defaults))
        if let local = defaults.string(forKey: SharerID.key).flatMap(UUID.init(uuidString:)) { ids.insert(local) }
        return ids
    }

    /// The service gave this install `id`.
    static func adopt(_ id: UUID, in defaults: UserDefaults) {
        var ids = all(in: defaults)
        ids.insert(id)
        defaults.set(ids.map(\.uuidString).sorted(), forKey: allKey)
        defaults.set(id.uuidString, forKey: key)
    }
}

// MARK: - Keychain

/// The session as one generic-password item, readable after the first unlock
/// and never synced or restored to another device: a second phone is a second
/// anonymous player until sign-in (0.9.0) links them.
struct KeychainSessionVault: SessionVault {
    private let service: String
    private let account: String

    /// `account` is injected so tests never touch the app's own session.
    init(account: String = "anonymous") {
        service = (Bundle.main.bundleIdentifier ?? "abe.movie-quiz") + ".service-session"
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> ServiceSession? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(ServiceSession.self, from: data)
    }

    /// Replaced in place, never deleted first: a kill between a delete and an
    /// add would leave no session, and the next launch would be a new player.
    func save(_ session: ServiceSession?) {
        guard let session else {
            SecItemDelete(query as CFDictionary)
            return
        }
        guard let data = try? JSONEncoder().encode(session) else { return }
        let update = [kSecValueData as String: data] as CFDictionary
        if SecItemUpdate(query as CFDictionary, update) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
