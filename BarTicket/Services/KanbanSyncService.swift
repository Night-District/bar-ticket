import Foundation

/// Periodically fetches the selected project's board from GitHub and publishes
/// it into AppState. Refreshes every 60 seconds while running, and on demand
/// (e.g. when the Dynamic Island expands).
@MainActor
final class KanbanSyncService {

    private weak var appState: AppState?
    private var timer: Timer?
    private var inFlight: Task<Void, Never>?
    private var lastProjectNodeId: String?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        stop()
        refresh(force: true)
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        inFlight?.cancel()
        inFlight = nil
    }

    /// Trigger an immediate refresh. Cancels any in-flight fetch.
    func refresh(force: Bool) {
        guard let appState else { return }
        guard let token = appState.githubToken else {
            appState.kanbanBoard = nil
            return
        }
        guard let projectId = appState.activeWatchedDirectory?.selectedProjectNodeId else {
            // No project selected for active dir — clear board but keep service running
            if lastProjectNodeId != nil {
                appState.kanbanBoard = nil
                lastProjectNodeId = nil
            }
            return
        }

        // Clear the board if the selected project changed so the UI shows a loading state
        if projectId != lastProjectNodeId {
            appState.kanbanBoard = nil
            lastProjectNodeId = projectId
        } else if !force, appState.kanbanBoard != nil {
            // Polling refresh with existing data — leave board in place during fetch
        }

        inFlight?.cancel()
        inFlight = Task { @MainActor [weak self] in
            do {
                let board = try await GitHubProjectsClient.fetchBoard(
                    projectNodeId: projectId,
                    token: token
                )
                guard !Task.isCancelled else { return }
                guard let state = self?.appState else { return }
                state.kanbanBoard = board
                state.kanbanFetchError = nil
                state.islandController?.viewModel.kanbanBoard = board
                state.islandController?.viewModel.kanbanProjectName = board.projectTitle
                state.islandController?.viewModel.kanbanFetchError = nil
            } catch {
                guard !Task.isCancelled else { return }
                guard let state = self?.appState else { return }
                state.kanbanFetchError = error.localizedDescription
                state.islandController?.viewModel.kanbanFetchError = error.localizedDescription
                print("[BarTicket] Kanban fetch failed: \(error)")
            }
        }
    }
}
