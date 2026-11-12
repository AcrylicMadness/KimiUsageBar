import Foundation
import KimiUsageBarCore

enum KimiRegion: String, CaseIterable, Identifiable {
    case china
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .china: "Kimi.com"
        case .global: "Kimi.ai"
        }
    }

    var apiBaseURL: URL {
        URL(string: "https://api.kimi.\(rawValue == "china" ? "com" : "ai")/coding/v1")!
    }

    var oauthHost: URL {
        URL(string: "https://auth.kimi.\(rawValue == "china" ? "com" : "ai")")!
    }

    var consoleURL: URL {
        URL(string: "https://www.kimi.\(rawValue == "china" ? "com" : "ai")/code/console")!
    }
}

struct KimiEndpoint {
    let apiBaseURL: URL
    let oauthHost: URL
    let consoleURL: URL
    let credentialName: String

    static func load(region: KimiRegion) -> KimiEndpoint {
        let fallback = KimiEndpoint(
            apiBaseURL: region.apiBaseURL,
            oauthHost: region.oauthHost,
            consoleURL: region.consoleURL,
            credentialName: "kimi-code"
        )
        let home = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"]
            .map { NSString(string: $0).expandingTildeInPath }
            ?? NSHomeDirectory().appending("/.kimi-code")
        let configURL = URL(fileURLWithPath: home).appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return fallback }

        let provider = section(named: "providers.\"managed:kimi-code\"", in: text)
        let oauth = section(named: "providers.\"managed:kimi-code\".oauth", in: text)
        let configuredBase = provider.flatMap { value(for: "base_url", in: $0) }
        let configuredHost = oauth.flatMap { value(for: "oauth_host", in: $0) }
        let suffix = region == .china ? "com" : "ai"
        guard let configuredBase,
              configuredBase.contains("kimi.\(suffix)/coding"),
              let apiBaseURL = URL(string: configuredBase) else { return fallback }

        let credentialKey = oauth.flatMap { value(for: "key", in: $0) } ?? "oauth/kimi-code"
        let credentialName = credentialKey.replacingOccurrences(of: "oauth/", with: "")
        guard credentialName == URL(fileURLWithPath: credentialName).lastPathComponent,
              !credentialName.hasPrefix(".") else { return fallback }

        return KimiEndpoint(
            apiBaseURL: apiBaseURL,
            oauthHost: configuredHost.flatMap(URL.init(string:)) ?? region.oauthHost,
            consoleURL: region.consoleURL,
            credentialName: credentialName
        )
    }

    static var preferredRegion: KimiRegion {
        let home = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"]
            .map { NSString(string: $0).expandingTildeInPath }
            ?? NSHomeDirectory().appending("/.kimi-code")
        let configURL = URL(fileURLWithPath: home).appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let provider = section(named: "providers.\"managed:kimi-code\"", in: text),
              let baseURL = value(for: "base_url", in: provider) else { return .china }
        return baseURL.contains("kimi.ai/") ? .global : .china
    }

    private static func section(named name: String, in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(name)]" }) else {
            return nil
        }
        let end = lines[(start + 1)...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("[")
        }) ?? lines.count
        return lines[(start + 1)..<end].joined(separator: "\n")
    }

    private static func value(for key: String, in section: String) -> String? {
        for line in section.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0] == key else { continue }
            return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}

enum UsageClientError: LocalizedError {
    case notSignedIn
    case invalidCredentials
    case unauthorized
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Sign in to Kimi Code with `kimi login`, then refresh."
        case .invalidCredentials:
            "The Kimi Code sign-in could not be read. Run `kimi login` again."
        case .unauthorized:
            "Your Kimi Code session expired. Run `kimi login`, then refresh."
        case .httpStatus(let status):
            "Kimi returned HTTP \(status). Try again in a moment."
        case .invalidResponse:
            "Kimi returned an unexpected response."
        }
    }
}

private struct OAuthToken: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
    }
}

private struct RefreshedToken: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

actor UsageClient {
    private let session: URLSession
    private var refreshedToken: OAuthToken?
    private var sourceRefreshToken: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(region: KimiRegion) async throws -> UsageSnapshot {
        let endpoint = KimiEndpoint.load(region: region)
        var token = try currentToken(endpoint: endpoint)
        if token.expiresAt <= Date().addingTimeInterval(300).timeIntervalSince1970 {
            token = try await refresh(token, endpoint: endpoint)
        }

        do {
            return try await requestUsage(token: token, endpoint: endpoint)
        } catch UsageClientError.unauthorized {
            token = try await refresh(token, endpoint: endpoint)
            return try await requestUsage(token: token, endpoint: endpoint)
        }
    }

    private func currentToken(endpoint: KimiEndpoint) throws -> OAuthToken {
        let home = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"]
            .map { NSString(string: $0).expandingTildeInPath }
            ?? NSHomeDirectory().appending("/.kimi-code")
        let url = URL(fileURLWithPath: home)
            .appendingPathComponent("credentials/\(endpoint.credentialName).json")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UsageClientError.notSignedIn
        }
        do {
            let stored = try JSONDecoder().decode(OAuthToken.self, from: Data(contentsOf: url))
            guard !stored.accessToken.isEmpty, !stored.refreshToken.isEmpty else {
                throw UsageClientError.invalidCredentials
            }
            if let refreshedToken, sourceRefreshToken == stored.refreshToken {
                return refreshedToken
            }
            sourceRefreshToken = stored.refreshToken
            return stored
        } catch let error as UsageClientError {
            throw error
        } catch {
            throw UsageClientError.invalidCredentials
        }
    }

    private func requestUsage(token: OAuthToken, endpoint: KimiEndpoint) async throws -> UsageSnapshot {
        var request = URLRequest(url: endpoint.apiBaseURL.appendingPathComponent("usages"))
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UsageClientError.invalidResponse
        }
        switch response.statusCode {
        case 200 ... 299:
            return try UsagePayloadDecoder.decode(data)
        case 401, 403:
            throw UsageClientError.unauthorized
        default:
            throw UsageClientError.httpStatus(response.statusCode)
        }
    }

    private func refresh(_ token: OAuthToken, endpoint: KimiEndpoint) async throws -> OAuthToken {
        var request = URLRequest(url: endpoint.oauthHost.appendingPathComponent("api/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: "17e5f671-d194-4dfb-9706-5516cb48c098"),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: token.refreshToken)
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UsageClientError.invalidResponse
        }
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw UsageClientError.unauthorized
            }
            throw UsageClientError.httpStatus(response.statusCode)
        }

        do {
            let refreshed = try JSONDecoder().decode(RefreshedToken.self, from: data)
            let token = OAuthToken(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken,
                expiresAt: Date().addingTimeInterval(refreshed.expiresIn).timeIntervalSince1970,
                expiresIn: refreshed.expiresIn
            )
            refreshedToken = token
            return token
        } catch {
            throw UsageClientError.invalidResponse
        }
    }
}
