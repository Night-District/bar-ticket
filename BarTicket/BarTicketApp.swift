import SwiftUI
import SwiftData

@main
struct BarTicketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Bar Ticket", systemImage: "ticket.fill") {
            SettingsView()
                .environment(appDelegate.appState)
                .modelContainer(appDelegate.modelContainer)
                .frame(width: 380, height: 440)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    let modelContainer: ModelContainer = {
        let schema = Schema([
            AppSettings.self,
            WatchedDirectory.self,
            SeenTodo.self
        ])
        let config = ModelConfiguration("BarTicket", isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrap()
    }

    private func bootstrap() {
        let context = modelContainer.mainContext

        // Load token
        appState.loadToken()

        // Seed AppSettings if needed
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        if (try? context.fetchCount(settingsDescriptor)) == 0 {
            context.insert(AppSettings())
            try? context.save()
        }

        // Populate recent issues from SwiftData
        var seenDescriptor = FetchDescriptor<SeenTodo>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let seenTodos = try? context.fetch(seenDescriptor) {
            appState.recentIssues = seenTodos
                .filter { $0.issueURL != nil }
                .prefix(20)
                .map { todo in
                    CreatedIssue(
                        title: todo.title,
                        issueNumber: todo.issueNumber ?? 0,
                        repoFullName: todo.repoFullName ?? "",
                        issueURL: todo.issueURL ?? "",
                        createdAt: todo.createdAt
                    )
                }
        }

        // Initialize services
        setupFileWatcher(context: context)
        setupDynamicIsland()

        print("[BarTicket] Bootstrap complete. Token: \(appState.githubToken != nil ? "present" : "missing")")
    }

    private func setupFileWatcher(context: ModelContext) {
        let watcher = FileWatcher()
        appState.fileWatcher = watcher

        // Load seen hashes
        let seenDescriptor = FetchDescriptor<SeenTodo>()
        if let seenTodos = try? context.fetch(seenDescriptor) {
            watcher.loadSeenHashes(Set(seenTodos.map(\.contentHash)))
        }

        // Handle new TODOs
        watcher.onTodoDetected = { [weak self] todo in
            print("[BarTicket] TODO detected: \"\(todo.title)\" in \(todo.filePath):\(todo.lineNumber)")
            DispatchQueue.main.async {
                self?.handleNewTodo(todo, context: context)
            }
        }

        // Start watching enabled directories
        let dirDescriptor = FetchDescriptor<WatchedDirectory>()
        if let directories = try? context.fetch(dirDescriptor) {
            let enabledPaths = directories.filter(\.isEnabled).map(\.path)
            if !enabledPaths.isEmpty {
                print("[BarTicket] Starting watcher for \(enabledPaths.count) directory(ies): \(enabledPaths)")
                watcher.startWatching(directories: enabledPaths, performInitialScan: true)
            } else {
                print("[BarTicket] No watched directories configured")
            }
        }
    }

    private func setupDynamicIsland() {
        appState.islandController = DynamicIslandController()
    }

    // MARK: - TODO Handling Pipeline

    @MainActor
    private func handleNewTodo(_ todo: ParsedTodo, context: ModelContext) {
        guard appState.isWatchingEnabled else { return }
        guard let token = appState.githubToken else {
            appState.showIsland(state: .error(message: "No GitHub token configured"))
            return
        }

        // Show detecting state
        appState.showIsland(state: .detecting(title: todo.title))

        // Resolve git repo
        guard let repoInfo = GitResolver.resolve(filePath: todo.filePath) else {
            appState.showIsland(state: .error(message: "Not a GitHub repository"))
            return
        }

        Task { @MainActor in
            // Hold detecting state so user can read it
            try? await Task.sleep(for: .seconds(1.0))

            // Transition to creating state
            appState.showIsland(state: .creating(title: todo.title))
            let creatingShownAt = ContinuousClock.now

            do {
                let response = try await GitHubClient.createIssue(
                    owner: repoInfo.owner,
                    repo: repoInfo.repo,
                    title: todo.title,
                    body: todo.issueBody,
                    token: token
                )

                // Ensure creating state is visible for at least 1 second
                let elapsed = ContinuousClock.now - creatingShownAt
                if elapsed < .seconds(1.0) {
                    try? await Task.sleep(for: .seconds(1.0) - elapsed)
                }

                // Append issue reference to the source file
                appendIssueReference(
                    filePath: todo.filePath,
                    lineNumber: todo.lineNumber,
                    issueNumber: response.number,
                    issueURL: response.htmlUrl
                )

                // Save to SwiftData
                let seenTodo = SeenTodo(
                    contentHash: todo.contentHash,
                    filePath: todo.filePath,
                    lineNumber: todo.lineNumber,
                    title: todo.title,
                    issueURL: response.htmlUrl,
                    issueNumber: response.number,
                    repoFullName: repoInfo.fullName
                )
                context.insert(seenTodo)
                try? context.save()

                // Track in recent issues
                let created = CreatedIssue(
                    title: todo.title,
                    issueNumber: response.number,
                    repoFullName: repoInfo.fullName,
                    issueURL: response.htmlUrl,
                    createdAt: Date()
                )
                appState.addRecentIssue(created)

                // Show confirmed
                appState.showIsland(state: .confirmed(
                    title: todo.title,
                    repoFullName: repoInfo.fullName,
                    issueNumber: response.number,
                    issueURL: response.htmlUrl
                ))

                print("[BarTicket] Issue created: #\(response.number) on \(repoInfo.fullName)")
            } catch {
                appState.showIsland(state: .error(message: error.localizedDescription))
                print("[BarTicket] Error creating issue: \(error)")
            }
        }
    }

    private func appendIssueReference(filePath: String, lineNumber: Int, issueNumber: Int, issueURL: String) {
        guard var lines = try? String(contentsOfFile: filePath, encoding: .utf8)
                .components(separatedBy: .newlines) else { return }

        let index = lineNumber - 1
        guard index >= 0, index < lines.count else { return }

        let line = lines[index]
        let ref = "(#\(issueNumber) \(issueURL))"

        // Don't append if already has a reference
        guard !line.contains("(#\(issueNumber)") else { return }

        lines[index] = line + " " + ref

        let updated = lines.joined(separator: "\n")
        try? updated.write(toFile: filePath, atomically: true, encoding: .utf8)

        // Update the file cache so this edit doesn't re-trigger detection
        appState.fileWatcher?.updateCache(path: filePath, content: updated)
    }
}
