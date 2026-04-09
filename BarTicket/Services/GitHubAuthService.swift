import AppKit
import Alamofire

private struct TokenExchangeResponse: Decodable {
    let accessToken: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
    }
}

private struct UserResponse: Decodable {
    let login: String
    let name: String?
    let avatarUrl: String
    let email: String?
    let htmlUrl: String
    let publicRepos: Int

    enum CodingKeys: String, CodingKey {
        case login, name, email
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
        case publicRepos = "public_repos"
    }
}

@Observable
final class GitHubAuthService {
    private(set) var isExchangingToken = false
    private(set) var error: String?
    private var pendingState: String?

    func startOAuthFlow() {
        let state = UUID().uuidString
        pendingState = state

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Constants.githubOAuthClientID),
            URLQueryItem(name: "redirect_uri", value: Constants.githubOAuthCallbackURL),
            URLQueryItem(name: "scope", value: Constants.githubOAuthScopes),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    func handleCallback(url: URL) async -> (token: String, user: GitHubUser)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == pendingState else {
            await MainActor.run { error = "Invalid OAuth callback" }
            return nil
        }

        pendingState = nil

        await MainActor.run {
            isExchangingToken = true
            error = nil
        }

        do {
            let token = try await exchangeCode(code)
            let user = try await fetchAuthenticatedUser(token: token)
            await MainActor.run { isExchangingToken = false }
            return (token: token, user: user)
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isExchangingToken = false
            }
            return nil
        }
    }

    func fetchAuthenticatedUser(token: String) async throws -> GitHubUser {
        let response = try await AF.request(
            "\(Constants.githubAPIURL)/user",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/vnd.github+json"
            ]
        )
        .serializingDecodable(UserResponse.self)
        .value

        return GitHubUser(
            login: response.login,
            name: response.name,
            avatarUrl: response.avatarUrl,
            email: response.email,
            htmlUrl: response.htmlUrl,
            publicRepos: response.publicRepos
        )
    }

    private func exchangeCode(_ code: String) async throws -> String {
        let response = try await AF.request(
            Constants.githubOAuthProxyURL,
            method: .post,
            parameters: ["code": code],
            encoder: JSONParameterEncoder.default
        )
        .serializingDecodable(TokenExchangeResponse.self)
        .value

        if let error = response.error {
            throw GitHubAuthError.exchangeFailed(error)
        }

        guard let token = response.accessToken else {
            throw GitHubAuthError.exchangeFailed("No access token returned")
        }

        return token
    }
}

enum GitHubAuthError: LocalizedError {
    case exchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .exchangeFailed(let message): return "Token exchange failed: \(message)"
        }
    }
}
