import Foundation
import SwiftData

enum IslandState: Equatable {
    case hidden
    case detecting(title: String)
    case expanding(title: String)
    case creating(title: String)
    case updating(title: String)
    case confirmed(
        title: String,
        repoFullName: String,
        issueNumber: Int,
        issueURL: String,
        projectName: String?,
        projectURL: String?,
        projectFailed: Bool,
        isV2Project: Bool
    )
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
    var githubUser: GitHubUser?
    var islandState: IslandState = .hidden
    var recentIssues: [CreatedIssue] = []

    // Services
    var fileWatcher: FileWatcher?
    var islandController: DynamicIslandController?
    let authService = GitHubAuthService()

    var isAuthenticated: Bool { githubToken != nil }

    func loadAuth() {
        // Prefer OAuth token; fall back to legacy PAT and migrate
        if let oauthToken = KeychainService.read(key: .githubOAuthToken) {
            githubToken = oauthToken
        } else if let legacyToken = KeychainService.read(key: .githubToken) {
            // Migrate PAT to OAuth key
            try? KeychainService.save(key: .githubOAuthToken, value: legacyToken)
            KeychainService.delete(key: .githubToken)
            githubToken = legacyToken
        }
    }

    func saveAuth(token: String, user: GitHubUser) throws {
        try KeychainService.save(key: .githubOAuthToken, value: token)
        githubToken = token
        githubUser = user
    }

    func fetchUserIfNeeded() async {
        guard let token = githubToken, githubUser == nil else { return }
        githubUser = try? await authService.fetchAuthenticatedUser(token: token)
    }

    func signOut() {
        KeychainService.delete(key: .githubOAuthToken)
        KeychainService.delete(key: .githubToken)
        githubToken = nil
        githubUser = nil
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
        print("[BarTicket] showIsland called, controller exists: \(islandController != nil)")
        islandState = state
        islandController?.show(state: state)
    }

    @MainActor
    func dismissIsland() {
        islandState = .hidden
        islandController?.dismiss()
    }
}
