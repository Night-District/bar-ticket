import Foundation
import Alamofire

/// One-shot helper that inspects the `X-OAuth-Scopes` header returned by
/// GitHub's REST API to determine whether the current OAuth token has the
/// scopes required for Projects v2 access.
enum GitHubScopeChecker {

    /// Returns `true` if the token has a Projects-capable scope.
    /// Defaults to `true` on network failure — we'd rather let requests fail
    /// naturally than falsely claim the user needs to reauth.
    static func hasProjectScope(token: String) async -> Bool {
        let request = AF.request(
            "\(Constants.githubAPIURL)/user",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/vnd.github+json"
            ]
        )

        let response = await request.serializingData().response

        guard let httpResponse = response.response else {
            return true
        }

        let scopeHeader = (httpResponse.value(forHTTPHeaderField: "X-OAuth-Scopes") ?? "")
        let scopes = Set(
            scopeHeader
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        )

        return !scopes.isDisjoint(with: Constants.requiredProjectScopes)
    }
}
