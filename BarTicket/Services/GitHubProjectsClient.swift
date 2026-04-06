import Foundation
import Alamofire

// MARK: - Response Models

private struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}

private struct FetchProjectsData: Decodable {
    let organization: OwnerProjectsData?
    let user: OwnerProjectsData?
}

private struct OwnerProjectsData: Decodable {
    let projectsV2: ProjectV2Connection?
}

private struct ProjectV2Connection: Decodable {
    let nodes: [ProjectV2Node]
}

private struct ProjectV2Node: Decodable {
    let id: String
    let title: String
    let url: String
}

private struct AddV2ItemData: Decodable {
    let addProjectV2ItemById: AddV2ItemResult?
}

private struct AddV2ItemResult: Decodable {
    let item: AddedItem?
}

private struct AddedItem: Decodable {
    let id: String
}

// MARK: - Error

enum GitHubProjectsError: LocalizedError {
    case noToken
    case graphQLError(String)
    case assignmentFailed

    var errorDescription: String? {
        switch self {
        case .noToken:              return "No GitHub token configured"
        case .graphQLError(let m):  return m
        case .assignmentFailed:     return "Failed to assign issue to project"
        }
    }
}

// MARK: - Client

enum GitHubProjectsClient {

    private static let graphqlURL = "https://api.github.com/graphql"

    private static func headers(token: String) -> HTTPHeaders {
        [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json"
        ]
    }

    // MARK: Fetch Projects

    /// Fetches v2 projects for the given owner (org or user).
    /// Queries both organization and user — whichever matches the login returns data.
    static func fetchProjects(owner: String, token: String) async throws -> [ProjectCache] {
        let query = """
        query FetchOwnerProjects($owner: String!) {
          organization(login: $owner) {
            projectsV2(first: 50) {
              nodes { id title url }
            }
          }
          user(login: $owner) {
            projectsV2(first: 50) {
              nodes { id title url }
            }
          }
        }
        """

        let body: [String: Any] = [
            "query": query,
            "variables": ["owner": owner]
        ]

        let response = try await AF.request(
            graphqlURL,
            method: .post,
            parameters: body,
            encoding: JSONEncoding.default,
            headers: headers(token: token)
        )
        .validate()
        .serializingDecodable(GraphQLResponse<FetchProjectsData>.self)
        .value

        // GitHub returns partial errors when one of organization/user doesn't match the login
        // (e.g. querying user(login:) for an org). This is expected — log and continue.
        if let errors = response.errors, !errors.isEmpty {
            let messages = errors.map(\.message).joined(separator: "; ")
            if response.data == nil {
                throw GitHubProjectsError.graphQLError(messages)
            }
            print("[BarTicket] GraphQL partial errors (non-fatal): \(messages)")
        }

        var results: [ProjectCache] = []

        for ownerData in [response.data?.organization, response.data?.user].compactMap({ $0 }) {
            for node in ownerData.projectsV2?.nodes ?? [] {
                results.append(ProjectCache(
                    projectNodeId: node.id,
                    displayName: node.title,
                    owner: owner,
                    isV2: true,
                    projectURL: node.url
                ))
            }
        }

        return results
    }

    // MARK: Add Issue to Project

    /// Adds an issue to a v2 project using the addProjectV2ItemById mutation.
    static func addIssueToProject(
        issueNodeId: String,
        project: ProjectCache,
        token: String
    ) async throws {
        let mutation = """
        mutation AddIssueToProjectV2($projectId: ID!, $contentId: ID!) {
          addProjectV2ItemById(input: { projectId: $projectId, contentId: $contentId }) {
            item { id }
          }
        }
        """

        let body: [String: Any] = [
            "query": mutation,
            "variables": ["projectId": project.projectNodeId, "contentId": issueNodeId]
        ]

        let response = try await AF.request(
            graphqlURL,
            method: .post,
            parameters: body,
            encoding: JSONEncoding.default,
            headers: headers(token: token)
        )
        .validate()
        .serializingDecodable(GraphQLResponse<AddV2ItemData>.self)
        .value

        if let errors = response.errors, !errors.isEmpty {
            throw GitHubProjectsError.graphQLError(errors.map(\.message).joined(separator: "; "))
        }

        guard response.data?.addProjectV2ItemById?.item != nil else {
            throw GitHubProjectsError.assignmentFailed
        }
    }
}
