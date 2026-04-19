import Foundation
import SwiftUI
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
    let views: ProjectV2ViewConnection?
}

private struct ProjectV2ViewConnection: Decodable {
    let nodes: [ProjectV2View]?
}

private struct ProjectV2View: Decodable {
    let layout: String?
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

// MARK: FetchBoard decodables

private struct FetchBoardData: Decodable {
    let node: ProjectBoardNode?
}

private struct ProjectBoardNode: Decodable {
    let id: String
    let title: String?
    let url: String?
    let field: ProjectStatusField?
    let items: ProjectBoardItemConnection?
}

private struct ProjectStatusField: Decodable {
    let options: [ProjectStatusOption]?
}

private struct ProjectStatusOption: Decodable {
    let id: String
    let name: String
    let color: String
}

private struct ProjectBoardItemConnection: Decodable {
    let nodes: [ProjectBoardItem]?
}

private struct ProjectBoardItem: Decodable {
    let id: String
    let content: ProjectBoardItemContent?
    let fieldValueByName: ProjectItemStatusValue?
}

private struct ProjectBoardItemContent: Decodable {
    let typename: String?
    let number: Int?
    let title: String?
    let body: String?
    let url: String?
    let state: String?
    let labels: ProjectBoardLabelConnection?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case number, title, body, url, state, labels
    }
}

private struct ProjectBoardLabelConnection: Decodable {
    let nodes: [ProjectBoardLabel]?
}

private struct ProjectBoardLabel: Decodable {
    let name: String
    let color: String
}

private struct ProjectItemStatusValue: Decodable {
    let optionId: String?
    let name: String?
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
              nodes { id title url views(first: 10) { nodes { layout } } }
            }
          }
          user(login: $owner) {
            projectsV2(first: 50) {
              nodes { id title url views(first: 10) { nodes { layout } } }
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
                let hasBoardLayout = node.views?.nodes?.contains { $0.layout == "BOARD_LAYOUT" } ?? false
                results.append(ProjectCache(
                    projectNodeId: node.id,
                    displayName: node.title,
                    owner: owner,
                    isV2: true,
                    projectURL: node.url,
                    hasBoardLayout: hasBoardLayout
                ))
            }
        }

        return results
    }

    // MARK: Fetch Board

    static func fetchBoard(projectNodeId: String, token: String) async throws -> KanbanBoard {
        let query = """
        query FetchBoard($projectId: ID!) {
          node(id: $projectId) {
            ... on ProjectV2 {
              id title url
              field(name: "Status") {
                ... on ProjectV2SingleSelectField {
                  options { id name color }
                }
              }
              items(first: 100) {
                nodes {
                  id
                  content {
                    __typename
                    ... on Issue {
                      number title body url state
                      labels(first: 10) { nodes { name color } }
                    }
                  }
                  fieldValueByName(name: "Status") {
                    ... on ProjectV2ItemFieldSingleSelectValue { optionId name }
                  }
                }
              }
            }
          }
        }
        """

        let body: [String: Any] = [
            "query": query,
            "variables": ["projectId": projectNodeId]
        ]

        let response = try await AF.request(
            graphqlURL,
            method: .post,
            parameters: body,
            encoding: JSONEncoding.default,
            headers: headers(token: token)
        )
        .validate()
        .serializingDecodable(GraphQLResponse<FetchBoardData>.self)
        .value

        if let errors = response.errors, !errors.isEmpty, response.data?.node == nil {
            throw GitHubProjectsError.graphQLError(errors.map(\.message).joined(separator: "; "))
        }

        guard let node = response.data?.node else {
            throw GitHubProjectsError.graphQLError("Project not found")
        }

        let options = node.field?.options ?? []
        let noStatusId = "__no_status__"

        // Group items by option id
        var grouped: [String: [KanbanCard]] = [:]
        for item in node.items?.nodes ?? [] {
            guard let issue = item.content, issue.typename == "Issue",
                  let number = issue.number,
                  let title = issue.title,
                  let url = issue.url,
                  let state = issue.state else {
                continue
            }
            // Only show open issues on the board.
            guard state == "OPEN" else { continue }

            let labels: [KanbanLabel] = (issue.labels?.nodes ?? []).map { label in
                KanbanLabel(name: label.name, color: Color(githubLabelHex: label.color))
            }

            let card = KanbanCard(
                id: item.id,
                issueNumber: number,
                title: title,
                body: issue.body ?? "",
                issueURL: url,
                state: state,
                labels: labels
            )

            let key = item.fieldValueByName?.optionId ?? noStatusId
            grouped[key, default: []].append(card)
        }

        var columns: [KanbanColumn] = []

        // No-status column first (only if populated)
        if let noStatusCards = grouped[noStatusId], !noStatusCards.isEmpty {
            columns.append(KanbanColumn(
                id: noStatusId,
                name: "No Status",
                color: Color(red: 0.55, green: 0.57, blue: 0.62),
                cards: noStatusCards
            ))
        }

        // Then columns in the order returned by the field definition
        for option in options {
            columns.append(KanbanColumn(
                id: option.id,
                name: option.name,
                color: Color(githubOptionColor: option.color),
                cards: grouped[option.id] ?? []
            ))
        }

        // If there's no Status field at all, dump everything into a single All Issues column
        if options.isEmpty && columns.isEmpty {
            let allCards = grouped.values.flatMap { $0 }
            columns.append(KanbanColumn(
                id: "__all__",
                name: "All Issues",
                color: Color(red: 0.26, green: 0.59, blue: 0.98),
                cards: allCards
            ))
        }

        return KanbanBoard(
            projectNodeId: node.id,
            projectTitle: node.title ?? "",
            projectURL: node.url ?? "",
            columns: columns,
            fetchedAt: Date()
        )
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
