import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @Query(sort: \WatchedDirectory.addedAt, order: .reverse) private var directories: [WatchedDirectory]
    @Query(sort: \SeenTodo.createdAt, order: .reverse) private var seenTodos: [SeenTodo]

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
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .font(.caption)
                                            .foregroundStyle(.blue.opacity(0.7))
                                        Text(dir.displayPath)
                                            .font(.system(.caption, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
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
