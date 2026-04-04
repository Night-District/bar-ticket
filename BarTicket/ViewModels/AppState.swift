import Foundation
import SwiftData

enum IslandState: Equatable {
    case hidden
    case detecting(title: String)
    case creating(title: String)
    case confirmed(title: String, repoFullName: String, issueNumber: Int, issueURL: String)
    case error(message: String)
}

struct CreatedIssue: Identifiable {
    let id = UUID()
    let title: String
    let issueNumber: Int
    let repoFullName: String
    let issueURL: String
    let createdAt: Date
}

@Observable
final class AppState {
    var isWatchingEnabled = true
    var githubToken: String?
    var islandState: IslandState = .hidden
    var recentIssues: [CreatedIssue] = []

    // Services
    var fileWatcher: FileWatcher?
    var islandController: DynamicIslandController?

    func loadToken() {
        githubToken = KeychainService.read(key: .githubToken)
    }

    func saveToken(_ token: String) throws {
        try KeychainService.save(key: .githubToken, value: token)
        githubToken = token
    }

    func clearToken() {
        KeychainService.delete(key: .githubToken)
        githubToken = nil
    }

    func addRecentIssue(_ issue: CreatedIssue) {
        recentIssues.insert(issue, at: 0)
        if recentIssues.count > 20 {
            recentIssues = Array(recentIssues.prefix(20))
        }
    }

    /// Transition the Dynamic Island through the full flow
    @MainActor
    func showIsland(state: IslandState) {
        islandState = state
        islandController?.show(state: state)
    }

    @MainActor
    func dismissIsland() {
        islandState = .hidden
        islandController?.dismiss()
    }
}
