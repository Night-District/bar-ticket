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
    let projects: ClassicProjectConnection?
}

private struct ProjectV2Connection: Decodable {
    let nodes: [ProjectV2Node]
}

private struct ProjectV2Node: Decodable {
    let id: String
    let title: String
    let url: String
}

private struct ClassicProjectConnection: Decodable {
    let nodes: [ClassicProjectNode]
}

private struct ClassicProjectNode: Decodable {
    let id: String
    let name: String
    let url: String
    let columns: ClassicColumnConnection?
}

private struct ClassicColumnConnection: Decodable {
    let nodes: [ClassicColumnNode]
}

private struct ClassicColumnNode: Decodable {
    let id: String
}

private struct AddV2ItemData: Decodable {
    let addProjectV2ItemById: AddV2ItemResult?
}

private struct AddV2ItemResult: Decodable {
    let item: AddedItem?
}

private struct AddProjectCardData: Decodable {
    let addProjectCard: AddProjectCardResult?
}

private struct AddProjectCardResult: Decodable {
    let projectCard: AddedItem?
}

private struct AddedItem: Decodable {
    let id: String
}

// MARK: - Error

enum GitHubProjectsError: LocalizedError {
    case noToken
    case graphQLError(String)
    case noColumnsFound
    case assignmentFailed

    var errorDescription: String? {
        switch self {
        case .noToken:              return "No GitHub token configured"
        case .graphQLError(let m):  return m
        case .noColumnsFound:       return "Classic project has no columns"
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

    /// Fetches Classic and v2 projects for the given owner (org or user).
    /// Returns a flat list of ProjectCache objects ready to be inserted into SwiftData.
    static func fetchProjects(owner: String, token: String) async throws -> [ProjectCache] {
        let query = """
        query FetchOwnerProjects($owner: String!) {
          organization(login: $owner) {
            projectsV2(first: 50) {
              nodes { id title url }
            }
            projects(first: 50) {
              nodes {
                id name url
                columns(first: 1) { nodes { id } }
              }
            }
          }
          user(login: $owner) {
            projectsV2(first: 50) {
              nodes { id title url }
            }
            projects(first: 50) {
              nodes {
                id name url
                columns(first: 1) { nodes { id } }
              }
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

        if let errors = response.errors, !errors.isEmpty {
            throw GitHubProjectsError.graphQLError(errors.map(\.message).joined(separator: "; "))
        }

        var results: [ProjectCache] = []

        // Collect from org or user — whichever has data
        for ownerData in [response.data?.organization, response.data?.user].compactMap({ $0 }) {
            // v2 projects
            for node in ownerData.projectsV2?.nodes ?? [] {
                results.append(ProjectCache(
                    projectNodeId: node.id,
                    displayName: node.title,
                    owner: owner,
                    isV2: true,
                    projectURL: node.url
                ))
            }
            // Classic projects
            for node in ownerData.projects?.nodes ?? [] {
                let firstColumnId = node.columns?.nodes.first?.id
                results.append(ProjectCache(
                    projectNodeId: node.id,
                    displayName: node.name,
                    owner: owner,
                    isV2: false,
                    projectURL: node.url,
                    firstColumnNodeId: firstColumnId
                ))
            }
        }

        return results
    }

    // MARK: Add Issue to Project

    /// Adds an issue to a project. For v2 projects uses addProjectV2ItemById; for Classic
    /// projects uses addProjectCard into the first column.
    static func addIssueToProject(
        issueNodeId: String,
        project: ProjectCache,
        token: String
    ) async throws {
        if project.isV2 {
            try await addToV2Project(issueNodeId: issueNodeId, projectNodeId: project.projectNodeId, token: token)
        } else {
            guard let columnId = project.firstColumnNodeId else {
                throw GitHubProjectsError.noColumnsFound
            }
            try await addToClassicProject(issueNodeId: issueNodeId, columnNodeId: columnId, token: token)
        }
    }

    private static func addToV2Project(
        issueNodeId: String,
        projectNodeId: String,
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
            "variables": ["projectId": projectNodeId, "contentId": issueNodeId]
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

    private static func addToClassicProject(
        issueNodeId: String,
        columnNodeId: String,
        token: String
    ) async throws {
        let mutation = """
        mutation AddIssueToClassicProject($columnId: ID!, $contentId: ID!) {
          addProjectCard(input: { projectColumnId: $columnId, contentId: $contentId }) {
            projectCard { id }
          }
        }
        """

        let body: [String: Any] = [
            "query": mutation,
            "variables": ["columnId": columnNodeId, "contentId": issueNodeId]
        ]

        let response = try await AF.request(
            graphqlURL,
            method: .post,
            parameters: body,
            encoding: JSONEncoding.default,
            headers: headers(token: token)
        )
        .validate()
        .serializingDecodable(GraphQLResponse<AddProjectCardData>.self)
        .value

        if let errors = response.errors, !errors.isEmpty {
            throw GitHubProjectsError.graphQLError(errors.map(\.message).joined(separator: "; "))
        }

        guard response.data?.addProjectCard?.projectCard != nil else {
            throw GitHubProjectsError.assignmentFailed
        }
    }
}
