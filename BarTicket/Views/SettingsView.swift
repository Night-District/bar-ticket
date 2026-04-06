import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @Query(sort: \WatchedDirectory.addedAt, order: .reverse) private var directories: [WatchedDirectory]
    @Query(sort: \SeenTodo.createdAt, order: .reverse) private var seenTodos: [SeenTodo]
    @Query private var cachedProjects: [ProjectCache]

    @State private var tokenInput = ""
    @State private var showTokenField = false

    private var appSettings: AppSettings? { settings.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(.blue)
                
                Text("Bar Ticket")
                    .font(.headline)
                
                Spacer()
                
                Toggle("", isOn: watchingToggle)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                
                Text(appState.isWatchingEnabled ? "Active" : "Paused")
                    .font(.caption)
                    .foregroundStyle(appState.isWatchingEnabled ? .green : .secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // GitHub Token
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("GitHub Token", systemImage: "key.fill")
                                .font(.caption.bold())

                            if appState.githubToken != nil && !showTokenField {
                                HStack {
                                    Text("ghp_" + String(repeating: "\u{2022}", count: 16))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Change") {
                                        showTokenField = true
                                        tokenInput = ""
                                    }
                                    .font(.caption)
                                }
                            } else {
                                HStack(spacing: 8) {
                                    SecureField("ghp_...", text: $tokenInput)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.caption, design: .monospaced))

                                    Button("Save") {
                                        let trimmed = tokenInput.trimmingCharacters(in: .whitespaces)
                                        guard !trimmed.isEmpty else { return }
                                        try? appState.saveToken(trimmed)
                                        tokenInput = ""
                                        showTokenField = false
                                    }
                                    .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    // Watched Directories
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Watched Directories", systemImage: "folder.fill")
                                .font(.caption.bold())

                            if directories.isEmpty {
                                Text("No directories added yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(directories) { dir in
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.fill")
                                            .font(.caption)
                                            .foregroundStyle(.blue.opacity(0.7))
                                        Text(dir.displayPath)
                                            .font(.system(.caption, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        ProjectDropdownButton(
                                            directory: dir,
                                            cachedProjects: cachedProjects,
                                            token: appState.githubToken
                                        )
                                        Button {
                                            modelContext.delete(dir)
                                            try? modelContext.save()
                                            restartWatcher()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }

                            Button {
                                addDirectory()
                            } label: {
                                Label("Add Directory...", systemImage: "plus")
                                    .font(.caption)
                            }
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 2)
                    }

                    // Recent Issues
                    if !appState.recentIssues.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Recent Issues", systemImage: "checkmark.circle.fill")
                                    .font(.caption.bold())

                                ForEach(appState.recentIssues.prefix(5)) { issue in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                        Text("#\(issue.issueNumber)")
                                            .font(.system(.caption, design: .monospaced, weight: .bold))
                                        Text(issue.repoFullName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(issue.createdAt.formatted(.relative(presentation: .named)))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Button {
                                            if let url = URL(string: issue.issueURL) {
                                                NSWorkspace.shared.open(url)
                                            }
                                        } label: {
                                            Image(systemName: "arrow.up.right")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button("Quit Bar Ticket") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Text("v2.0.0")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Bindings

    private var watchingToggle: Binding<Bool> {
        Binding(
            get: { appState.isWatchingEnabled },
            set: { newValue in
                appState.isWatchingEnabled = newValue
                if let settings = appSettings {
                    settings.isWatchingEnabled = newValue
                    try? modelContext.save()
                }
                if newValue {
                    restartWatcher()
                } else {
                    appState.fileWatcher?.stopWatching()
                }
            }
        )
    }

    // MARK: - Actions

    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project directory to watch for TODO comments"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path()

        // Don't add duplicates
        guard !directories.contains(where: { $0.path == path }) else { return }

        let dir = WatchedDirectory(path: path)
        modelContext.insert(dir)
        try? modelContext.save()
        restartWatcher()
    }

    private func restartWatcher() {
        let enabledPaths = directories.filter(\.isEnabled).map(\.path)
        appState.fileWatcher?.startWatching(directories: enabledPaths, performInitialScan: true)
    }
}

// MARK: - ProjectDropdownButton

struct ProjectDropdownButton: View {
    let directory: WatchedDirectory
    let cachedProjects: [ProjectCache]
    let token: String?

    @Environment(\.modelContext) private var modelContext

    @State private var isFetching = false
    @State private var fetchError: String?

    private var selectedProject: ProjectCache? {
        guard let id = directory.selectedProjectNodeId else { return nil }
        return cachedProjects.first { $0.projectNodeId == id }
    }

    private var grouped: [(owner: String, projects: [ProjectCache])] {
        let byOwner = Dictionary(grouping: cachedProjects, by: \.owner)
        return byOwner.keys.sorted().map { owner in
            (owner: owner, projects: byOwner[owner]!.sorted { $0.displayName < $1.displayName })
        }
    }

    var body: some View {
        Menu {
            // Refresh option
            Button {
                Task { await fetchProjects() }
            } label: {
                if isFetching {
                    Label("Fetching…", systemImage: "arrow.clockwise")
                } else {
                    Label("Refresh Projects", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isFetching || token == nil)

            if let error = fetchError {
                Text("⚠ \(error)").foregroundStyle(.secondary)
            }

            if !cachedProjects.isEmpty {
                Divider()

                // No project option
                Button {
                    directory.selectedProjectNodeId = nil
                    try? modelContext.save()
                } label: {
                    HStack {
                        Text("No project")
                        if directory.selectedProjectNodeId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                // Grouped by owner
                ForEach(grouped, id: \.owner) { group in
                    Section(group.owner) {
                        ForEach(group.projects, id: \.projectNodeId) { project in
                            Button {
                                directory.selectedProjectNodeId = project.projectNodeId
                                try? modelContext.save()
                            } label: {
                                HStack {
                                    Image(systemName: project.isV2 ? "sparkles" : "folder.fill")
                                    Text(project.displayName)
                                    if directory.selectedProjectNodeId == project.projectNodeId {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedProject.map { $0.isV2 ? "sparkles" : "folder.badge.checkmark" } ?? "folder.badge.plus")
                    .font(.system(size: 10))
                    .foregroundStyle(selectedProject != nil ? .blue : .secondary)
                Text(selectedProject?.displayName ?? "Project")
                    .font(.caption2)
                    .foregroundStyle(selectedProject != nil ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.blue.opacity(selectedProject != nil ? 0.12 : 0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(.blue.opacity(selectedProject != nil ? 0.3 : 0.15), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onAppear {
            if cachedProjects.isEmpty, token != nil {
                Task { await fetchProjects() }
            }
        }
    }

    private func fetchProjects() async {
        guard let token else { return }

        // Determine owner from the directory's git remote
        guard let repoInfo = resolveOwner() else {
            fetchError = "Could not resolve git remote"
            return
        }

        isFetching = true
        fetchError = nil

        do {
            let projects = try await GitHubProjectsClient.fetchProjects(owner: repoInfo, token: token)

            // Upsert into cache
            let existingIds = Set(cachedProjects.map(\.projectNodeId))
            for project in projects {
                if !existingIds.contains(project.projectNodeId) {
                    modelContext.insert(project)
                }
            }
            try? modelContext.save()
        } catch {
            fetchError = error.localizedDescription
            print("[BarTicket] Failed to fetch projects: \(error)")
        }

        isFetching = false
    }

    private func resolveOwner() -> String? {
        // Use any file in the directory to resolve git remote
        let testPath = directory.path + "/.git/config"
        if let repoInfo = GitResolver.resolve(filePath: testPath) {
            return repoInfo.owner
        }
        // Fallback: try the directory path itself
        return GitResolver.resolve(filePath: directory.path + "/placeholder")?.owner
    }
}
