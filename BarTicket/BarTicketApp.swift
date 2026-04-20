import SwiftUI
import SwiftData

@main
struct BarTicketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    //TODO: fix/persisted-dynamic-island-state (#109 https://github.com/Night-District/bar-ticket/issues/109)
    // The Dynamic Island is currently showing when issues are not being created. Ensure that the dynamic island only appears during the issue creation flow and is dismissed afterward, rather than remaining visible indefinitely.
    
    //TODO: design/primary-color (#55 https://github.com/Night-District/bar-ticket/issues/55)
    // Set up primary color to use Night District's pink and implement a consistent color scheme across the app (island, menu, settings, etc.)
    var body: some Scene {
        MenuBarExtra("Bar Ticket", systemImage: "ticket.fill") {
            Group {
                if appDelegate.appState.isAuthenticated {
                    SettingsView()
                } else {
                    OnboardingView()
                }
            }
            .environment(appDelegate.appState)
            .modelContainer(appDelegate.modelContainer)
            .frame(width: 480, height: appDelegate.appState.isAuthenticated ? 440 : 320)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var foregroundAppWatcher: ForegroundAppWatcher?
    
    //TODO: persistence/swift-data-migration (#99 https://github.com/Night-District/bar-ticket/issues/99)
    // Implement a migration strategy for SwiftData models as the app evolves. This could involve lightweight migrations for simple changes or a more robust versioning system for complex schema updates.
    let modelContainer: ModelContainer = {
        let schema = Schema([
            AppSettings.self,
            WatchedDirectory.self,
            SeenTodo.self,
            ProjectCache.self,
            IssueTemplate.self
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
        Task { @MainActor in
            await appState.fetchUserIfNeeded()
            await appState.refreshProjectScopeCheck()
            appState.kanbanSync?.start()
            appState.refreshKanbanAmbient()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.scheme == "barticket" else { return }
        Task { @MainActor in
            if let result = await appState.authService.handleCallback(url: url) {
                try? appState.saveAuth(token: result.token, user: result.user)
                await appState.refreshProjectScopeCheck()
                appState.kanbanSync?.start()
                appState.refreshKanbanAmbient()
            }
        }
    }

    private func bootstrap() {
        let context = modelContainer.mainContext

        // Load auth (OAuth token with PAT migration fallback)
        appState.loadAuth()

        // Seed AppSettings if needed
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        if (try? context.fetchCount(settingsDescriptor)) == 0 {
            context.insert(AppSettings())
            try? context.save()
        }

        // Seed built-in issue templates if needed
        IssueTemplateService.seedIfNeeded(context: context)

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
        setupDynamicIsland(context: context)
        setupKanbanSync(context: context)
        setupActiveDirectoryDefault(context: context)
        setupForegroundAppWatcher(context: context)

        print("[BarTicket] Bootstrap complete. Token: \(appState.githubToken != nil ? "present" : "missing")")
    }

    private func setupFileWatcher(context: ModelContext) {
        let watcher = FileWatcher()
        appState.fileWatcher = watcher

        // Load seen hashes and issued todo records
        let seenDescriptor = FetchDescriptor<SeenTodo>()
        if let seenTodos = try? context.fetch(seenDescriptor) {
            watcher.loadSeenHashes(Set(seenTodos.map(\.contentHash)))
            let issuedRecords = seenTodos.compactMap { todo -> IssuedTodoRecord? in
                guard let issueNumber = todo.issueNumber,
                      let repoFullName = todo.repoFullName else { return nil }
                return IssuedTodoRecord(
                    issueNumber: issueNumber,
                    repoFullName: repoFullName,
                    contentHash: todo.contentHash,
                    issueURL: todo.issueURL,
                    title: todo.title
                )
            }
            watcher.loadIssuedTodos(issuedRecords)
        }

        // Handle new TODOs
        watcher.onTodoDetected = { [weak self] todo in
            print("[BarTicket] TODO detected: \"\(todo.title)\" in \(todo.filePath):\(todo.lineNumber)")
            DispatchQueue.main.async {
                self?.updateActiveDirectory(forFilePath: todo.filePath, context: context)
                self?.handleNewTodo(todo, context: context)
            }
        }

        // Handle updated TODOs (existing issue, body changed)
        watcher.onTodoUpdated = { [weak self] updated in
            print("[BarTicket] TODO updated: \"\(updated.new.title)\" issue #\(updated.old.issueNumber) on \(updated.old.repoFullName)")
            DispatchQueue.main.async {
                self?.updateActiveDirectory(forFilePath: updated.new.filePath, context: context)
                self?.handleUpdatedTodo(updated, context: context)
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

    private func setupDynamicIsland(context: ModelContext) {
        let controller = DynamicIslandController()
        appState.islandController = controller

        // "Select a Project" button in the empty Kanban state opens settings.
        controller.viewModel.kanbanOnSelectProject = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if !self.appState.isAuthenticated {
                    self.appState.authService.startOAuthFlow()
                } else if self.appState.needsProjectScope {
                    self.appState.authService.startOAuthFlow()
                } else {
                    // Pop the menu bar item open so the user can pick a project
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }

        controller.viewModel.kanbanOnRefresh = { [weak self] in
            self?.appState.kanbanSync?.refresh(force: true)
        }

        controller.viewModel.kanbanOnPickProject = { [weak self] nodeId in
            guard let self else { return }
            Task { @MainActor in
                self.handleProjectPick(nodeId: nodeId, context: context)
            }
        }
    }

    private func setupKanbanSync(context: ModelContext) {
        let sync = KanbanSyncService(appState: appState)
        appState.kanbanSync = sync
    }

    /// On launch, default the active directory to the first enabled watched
    /// directory that has a project selected, so the ambient Kanban has
    /// something to display before the user edits a file.
    private func setupActiveDirectoryDefault(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchedDirectory>()
        guard let directories = try? context.fetch(descriptor) else { return }
        let candidate = directories.first { $0.isEnabled && $0.selectedProjectNodeId != nil }
            ?? directories.first(where: \.isEnabled)
        guard let candidate else { return }

        let projectName: String? = {
            guard let id = candidate.selectedProjectNodeId else { return nil }
            let all = (try? context.fetch(FetchDescriptor<ProjectCache>())) ?? []
            return all.first { $0.projectNodeId == id }?.displayName
        }()
        appState.setActiveWatchedDirectory(candidate, projectName: projectName)
        refreshAvailableProjects(context: context)
    }

    private func setupForegroundAppWatcher(context: ModelContext) {
        let watcher = ForegroundAppWatcher()
        watcher.onDirectoryChange = { [weak self] url in
            guard let self, let url else { return }
            self.updateActiveDirectory(forURL: url, context: context)
        }
        watcher.start()
        foregroundAppWatcher = watcher
    }

    /// Resolve a directory URL from the frontmost window to a watched directory and set it active.
    /// Only acts when the URL falls inside a watched directory — unrelated apps are ignored.
    @MainActor
    private func updateActiveDirectory(forURL url: URL, context: ModelContext) {
        let descriptor = FetchDescriptor<WatchedDirectory>()
        guard let dirs = try? context.fetch(descriptor) else { return }
        let path = url.path
        let matched = dirs
            .filter { $0.isEnabled && path.hasPrefix($0.path) }
            .max(by: { $0.path.count < $1.path.count })
        guard let dir = matched else { return }
        guard appState.activeWatchedDirectory?.path != dir.path else { return }
        let projectName: String? = {
            guard let id = dir.selectedProjectNodeId else { return nil }
            return (try? context.fetch(FetchDescriptor<ProjectCache>()))?
                .first { $0.projectNodeId == id }?.displayName
        }()
        appState.setActiveWatchedDirectory(dir, projectName: projectName)
        refreshAvailableProjects(context: context)
    }

    /// Populates the notch's project picker with all projects linked to any watched directory.
    private func refreshAvailableProjects(context: ModelContext) {
        let dirs = (try? context.fetch(FetchDescriptor<WatchedDirectory>())) ?? []
        let linkedIds = Set(dirs.compactMap(\.selectedProjectNodeId))
        let all = (try? context.fetch(FetchDescriptor<ProjectCache>())) ?? []
        let projects = all
            .filter { linkedIds.contains($0.projectNodeId) }
            .map { (nodeId: $0.projectNodeId, name: $0.displayName) }
        appState.islandController?.viewModel.availableProjects = projects
    }

    /// Persists a manually selected project for the active directory and refreshes the board.
    @MainActor
    private func handleProjectPick(nodeId: String, context: ModelContext) {
        let projectName = (try? context.fetch(FetchDescriptor<ProjectCache>()))?
            .first { $0.projectNodeId == nodeId }?.displayName
        appState.kanbanProjectOverride = nodeId
        appState.islandController?.viewModel.kanbanProjectName = projectName
        appState.kanbanSync?.refresh(force: true)
    }

    /// Resolve a file path back to its watched directory and set it active.
    @MainActor
    private func updateActiveDirectory(forFilePath path: String, context: ModelContext) {
        let descriptor = FetchDescriptor<WatchedDirectory>()
        guard let directories = try? context.fetch(descriptor),
              let dir = directories.first(where: { path.hasPrefix($0.path) }) else { return }
        guard appState.activeWatchedDirectory?.path != dir.path else { return }
        let projectName: String? = {
            guard let id = dir.selectedProjectNodeId else { return nil }
            let all = (try? context.fetch(FetchDescriptor<ProjectCache>())) ?? []
            return all.first { $0.projectNodeId == id }?.displayName
        }()
        appState.setActiveWatchedDirectory(dir, projectName: projectName)
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
        let repoInfo: RepoInfo
        do {
            repoInfo = try GitResolver.resolve(filePath: todo.filePath)
        } catch {
            appState.showIsland(state: .error(message: error.localizedDescription))
            return
        }

        // Find the watched directory entry for this file (to check for a selected project)
        let dirDescriptor = FetchDescriptor<WatchedDirectory>()
        let watchedDir = (try? context.fetch(dirDescriptor))?
            .first { todo.filePath.hasPrefix($0.path) }

        Task { @MainActor in
            // Hold detecting state so user can read it
            try? await Task.sleep(for: .seconds(1.0))

            // AI expansion (if enabled)
            var issueTitle = todo.title
            var issueBody = todo.issueBody
            var issueLabels: [String] = []

            let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first
            if settings?.aiEnabled == true {
                appState.showIsland(state: .expanding(title: todo.title))
                let expandingShownAt = ContinuousClock.now
                print("[BarTicket] AI expansion started for: \"\(todo.title)\"")

                do {
                    let templates = IssueTemplateService.fetchAll(context: context)

                    // Read the source file for context
                    let fileContext = try? String(contentsOfFile: todo.filePath, encoding: .utf8)

                    // Look for CLAUDE.md in the git repo root
                    let claudeMDPath = repoInfo.rootPath + "/CLAUDE.md"
                    let claudeMD = try? String(contentsOfFile: claudeMDPath, encoding: .utf8)

                    let result = try await ClaudeClient.generateIssue(
                        rawTodo: todo.title,
                        templates: templates,
                        fileContext: fileContext,
                        claudeMD: claudeMD
                    )

                    issueTitle = result.title
                    issueBody = result.body
                    issueLabels = result.labels
                    print("[BarTicket] AI expansion succeeded: title=\"\(result.title)\" labels=\(result.labels)")
                } catch {
                    print("[BarTicket] AI expansion failed, using raw TODO: \(error)")
                    appState.showIsland(state: .error(message: "AI unavailable — using raw TODO"))
                    try? await Task.sleep(for: .seconds(1.5))
                }

                // Enforce minimum expanding display time
                let elapsed = ContinuousClock.now - expandingShownAt
                if elapsed < .seconds(Constants.claudeExpandDuration) {
                    try? await Task.sleep(for: .seconds(Constants.claudeExpandDuration) - elapsed)
                }
            }

            // Transition to creating state
            appState.showIsland(state: .creating(title: issueTitle))
            let creatingShownAt = ContinuousClock.now

            do {
                let response = try await GitHubClient.createIssue(
                    owner: repoInfo.owner,
                    repo: repoInfo.repo,
                    title: issueTitle,
                    body: issueBody,
                    labels: issueLabels,
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

                // Register with watcher so future edits trigger an update instead of a new issue
                appState.fileWatcher?.addIssuedTodo(IssuedTodoRecord(
                    issueNumber: response.number,
                    repoFullName: repoInfo.fullName,
                    contentHash: todo.contentHash,
                    issueURL: response.htmlUrl,
                    title: todo.title
                ))

                // Track in recent issues
                let created = CreatedIssue(
                    title: todo.title,
                    issueNumber: response.number,
                    repoFullName: repoInfo.fullName,
                    issueURL: response.htmlUrl,
                    createdAt: Date()
                )
                appState.addRecentIssue(created)

                // Attempt project assignment (non-blocking; issue already created)
                var projectName: String? = nil
                var projectURL: String? = nil
                var projectFailed = false

                var isV2Project = false

                if let selectedId = watchedDir?.selectedProjectNodeId {
                    let projectDescriptor = FetchDescriptor<ProjectCache>()
                    let project = (try? context.fetch(projectDescriptor))?
                        .first { $0.projectNodeId == selectedId }

                    if let project {
                        projectName = project.displayName
                        projectURL = project.projectURL
                        isV2Project = project.isV2

                        do {
                            try await GitHubProjectsClient.addIssueToProject(
                                issueNodeId: response.nodeId,
                                project: project,
                                token: token
                            )
                            print("[BarTicket] Issue #\(response.number) added to project '\(project.displayName)'")
                        } catch {
                            projectFailed = true
                            print("[BarTicket] Project assignment failed: \(error)")
                        }
                    }
                }

                // Show confirmed (with project info if applicable)
                appState.showIsland(state: .confirmed(
                    title: todo.title,
                    repoFullName: repoInfo.fullName,
                    issueNumber: response.number,
                    issueURL: response.htmlUrl,
                    projectName: projectName,
                    projectURL: projectURL,
                    projectFailed: projectFailed,
                    isV2Project: isV2Project
                ))

                print("[BarTicket] Issue created: #\(response.number) on \(repoInfo.fullName)")
            } catch {
                appState.showIsland(state: .error(message: error.localizedDescription))
                print("[BarTicket] Error creating issue: \(error)")
            }
        }
    }

    @MainActor
    private func handleUpdatedTodo(_ updated: UpdatedTodo, context: ModelContext) {
        guard appState.isWatchingEnabled else { return }
        guard let token = appState.githubToken else {
            appState.showIsland(state: .error(message: "No GitHub token configured"))
            return
        }

        let parts = updated.old.repoFullName.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else {
            appState.showIsland(state: .error(message: "Invalid repo: \(updated.old.repoFullName)"))
            return
        }
        let owner = String(parts[0])
        let repo = String(parts[1])

        appState.showIsland(state: .detecting(title: updated.new.title))

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))

            appState.showIsland(state: .updating(title: updated.new.title))
            let updatingShownAt = ContinuousClock.now

            do {
                _ = try await GitHubClient.updateIssue(
                    owner: owner,
                    repo: repo,
                    number: updated.old.issueNumber,
                    title: updated.new.title,
                    body: updated.new.issueBody,
                    token: token
                )

                let elapsed = ContinuousClock.now - updatingShownAt
                if elapsed < .seconds(1.0) {
                    try? await Task.sleep(for: .seconds(1.0) - elapsed)
                }

                // Commit new hash to watcher so subsequent saves without further
                // edits are no-ops rather than retrying the PATCH.
                appState.fileWatcher?.commitIssuedTodoUpdate(
                    new: IssuedTodoRecord(
                        issueNumber: updated.old.issueNumber,
                        repoFullName: updated.old.repoFullName,
                        contentHash: updated.new.contentHash,
                        issueURL: updated.old.issueURL,
                        title: updated.new.title
                    ),
                    oldHash: updated.old.contentHash
                )

                // Update SeenTodo in SwiftData
                let allTodos = (try? context.fetch(FetchDescriptor<SeenTodo>())) ?? []
                if let existing = allTodos.first(where: {
                    $0.issueNumber == updated.old.issueNumber && $0.repoFullName == updated.old.repoFullName
                }) {
                    existing.contentHash = updated.new.contentHash
                    existing.title = updated.new.title
                    try? context.save()
                }

                appState.showIsland(state: .confirmed(
                    title: updated.new.title,
                    repoFullName: updated.old.repoFullName,
                    issueNumber: updated.old.issueNumber,
                    issueURL: updated.old.issueURL ?? "",
                    projectName: nil,
                    projectURL: nil,
                    projectFailed: false,
                    isV2Project: false
                ))

                print("[BarTicket] Issue updated: #\(updated.old.issueNumber) on \(updated.old.repoFullName)")
            } catch {
                appState.showIsland(state: .error(message: error.localizedDescription))
                print("[BarTicket] Error updating issue: \(error)")
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
