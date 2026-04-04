import Foundation
import Alamofire

struct GitHubIssueResponse: Decodable {
    let id: Int
    let number: Int
    let htmlUrl: String
    let title: String

    enum CodingKeys: String, CodingKey {
        case id, number, title
        case htmlUrl = "html_url"
    }
}

enum GitHubClientError: LocalizedError {
    case noToken
    case rateLimited
    case repoNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No GitHub token configured"
        case .rateLimited:
            return "GitHub API rate limit exceeded"
        case .repoNotFound(let repo):
            return "Repository not found: \(repo)"
        }
    }
}

enum GitHubClient {

    private static func headers(token: String) -> HTTPHeaders {
        [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28"
        ]
    }

    static func createIssue(
        owner: String,
        repo: String,
        title: String,
        body: String,
        token: String
    ) async throws -> GitHubIssueResponse {
        let url = "\(Constants.githubAPIURL)/repos/\(owner)/\(repo)/issues"

        let parameters: [String: Any] = [
            "title": title,
            "body": body
        ]

        let response = AF.request(
            url,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: headers(token: token)
        )
        .validate(statusCode: 200..<300)

        do {
            return try await response
                .serializingDecodable(GitHubIssueResponse.self)
                .value
        } catch let afError as AFError {
            if let statusCode = afError.responseCode {
                switch statusCode {
                case 403:
                    throw GitHubClientError.rateLimited
                case 404:
                    throw GitHubClientError.repoNotFound("\(owner)/\(repo)")
                default:
                    throw afError
                }
            }
            throw afError
        }
    }
}
