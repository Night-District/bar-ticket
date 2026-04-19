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

    // Kanban
    var activeWatchedDirectory: WatchedDirectory?
    var kanbanProjectOverride: String?
    var kanbanBoard: KanbanBoard?
    var kanbanFetchError: String?
    var needsProjectScope: Bool = false

    // Services
    var fileWatcher: FileWatcher?
    var islandController: DynamicIslandController?
    var kanbanSync: KanbanSyncService?
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

    @MainActor
    func signOut() {
        KeychainService.delete(key: .githubOAuthToken)
        KeychainService.delete(key: .githubToken)
        githubToken = nil
        githubUser = nil
        needsProjectScope = false
        kanbanBoard = nil
        activeWatchedDirectory = nil
        kanbanSync?.stop()
        islandController?.disableAmbient()
    }

    /// Verify that the current token has a Projects-capable scope. Updates
    /// `needsProjectScope` — true means the user should reauth to use Kanban.
    func refreshProjectScopeCheck() async {
        guard let token = githubToken else {
            needsProjectScope = false
            return
        }
        let hasScope = await GitHubScopeChecker.hasProjectScope(token: token)
        needsProjectScope = !hasScope
    }

    /// Update the active watched directory based on file activity. The Kanban
    /// board follows whichever directory has been edited most recently.
    /// `projectName` lets the caller pass a cached display name so the
    /// compact notch has something to render before the first fetch lands.
    @MainActor
    func setActiveWatchedDirectory(_ directory: WatchedDirectory?, projectName: String?) {
        let oldProjectId = kanbanProjectOverride ?? activeWatchedDirectory?.selectedProjectNodeId
        let newProjectId = directory?.selectedProjectNodeId
        kanbanProjectOverride = nil
        activeWatchedDirectory = directory
        islandController?.viewModel.kanbanProjectName = projectName
        if oldProjectId != newProjectId {
            kanbanBoard = nil
            islandController?.viewModel.kanbanBoard = nil
            kanbanFetchError = nil
            islandController?.viewModel.kanbanFetchError = nil
        }
        refreshKanbanAmbient()
        kanbanSync?.refresh(force: true)
    }

    /// Reconcile ambient Kanban notch mode based on current state. Shows the
    /// compact Kanban notch whenever the user is authenticated — it acts as a
    /// persistent entry point (empty state if no project is selected).
    @MainActor
    func refreshKanbanAmbient() {
        guard let controller = islandController else { return }
        if isAuthenticated {
            controller.enableKanbanAmbient()
        } else {
            controller.disableAmbient()
        }
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
