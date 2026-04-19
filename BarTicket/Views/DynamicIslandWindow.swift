import AppKit
import SwiftUI
import DynamicNotchKit

enum IconAnimation: Equatable {
    case none
    case rotating
    case pulsing
}

enum NotchMode: Equatable {
    case kanban
    case pipeline
}

/// Unified state container read by the compact + expanded notch views. Owns
/// both the legacy "pipeline" fields (detecting → creating → confirmed) and
/// the Kanban board snapshot.
@MainActor
@Observable
final class NotchViewModel {
    // Shared
    var mode: NotchMode = .kanban

    // Pipeline state
    var icon: String = "circle.fill"
    var iconColor: Color = .blue
    var iconAnimation: IconAnimation = .none
    var title: String = ""
    var subtitle: String = ""
    var issueURL: String?
    var projectName: String?
    var projectURL: String?
    var projectFailed: Bool = false
    var isV2Project: Bool = false

    // Kanban state
    var kanbanBoard: KanbanBoard?
    var kanbanProjectName: String?
    var kanbanFetchError: String?
    var kanbanOnCardCopied: ((KanbanCard) -> Void)?
    var kanbanOnSelectProject: (() -> Void)?
    var kanbanOnExpand: (() -> Void)?
    var kanbanOnDismiss: (() -> Void)?
    var kanbanOnRefresh: (() -> Void)?
}

@MainActor
final class DynamicIslandController {
    private var notch: DynamicNotch<NotchExpandedView, NotchCompactLeading, NotchCompactTrailing>?
    let viewModel = NotchViewModel()
    private var dismissTask: Task<Void, Never>?
    private var returnToCompactTask: Task<Void, Never>?
    /// True when the Kanban ambient mode should be displayed whenever the
    /// pipeline is idle. Controlled by `enableKanbanAmbient()` / `disable…`.
    private var ambientEnabled = false

    //TODO: design/github-icons (#59 https://github.com/Night-District/bar-ticket/issues/59)
    // Download actual GitHub icon SVGs for projects, issues, branches, etc. and render them in the island instead of generic system icons.

    // MARK: - Ambient Kanban mode

    /// Called when Kanban should be displayed as the default/ambient notch state.
    /// Idempotent — safe to call repeatedly when the board refreshes.
    func enableKanbanAmbient() {
        ambientEnabled = true
        viewModel.mode = .kanban
        presentIfNeeded()
    }

    /// Hide the notch entirely. Used when no project is selected and no pipeline is active.
    func disableAmbient() {
        ambientEnabled = false
        if viewModel.mode == .kanban {
            teardown()
        }
    }

    // MARK: - Pipeline mode

    func show(state: IslandState) {
        dismissTask?.cancel()
        returnToCompactTask?.cancel()

        switch state {
        case .hidden:
            returnToAmbientOrHide()
            return

        case .detecting(let title):
            viewModel.mode = .pipeline
            viewModel.icon = "gear"
            viewModel.iconColor = .blue
            viewModel.iconAnimation = .rotating
            viewModel.title = "TODO detected"
            viewModel.subtitle = title
            resetPipelineExtras()

        case .expanding(let title):
            viewModel.mode = .pipeline
            viewModel.icon = "sparkles"
            viewModel.iconColor = .purple
            viewModel.iconAnimation = .pulsing
            viewModel.title = "Expanding with AI..."
            viewModel.subtitle = title
            resetPipelineExtras()

        case .creating(let title):
            viewModel.mode = .pipeline
            viewModel.icon = "arrow.trianglehead.2.counterclockwise"
            viewModel.iconColor = .orange
            viewModel.iconAnimation = .rotating
            viewModel.title = "Creating issue..."
            viewModel.subtitle = title
            resetPipelineExtras()

        case .updating(let title):
            viewModel.mode = .pipeline
            viewModel.icon = "arrow.trianglehead.clockwise"
            viewModel.iconColor = .cyan
            viewModel.iconAnimation = .rotating
            viewModel.title = "Updating issue..."
            viewModel.subtitle = title
            resetPipelineExtras()

        case .confirmed(_, let repoFullName, let issueNumber, let issueURL, let projectName, let projectURL, let projectFailed, let isV2):
            viewModel.mode = .pipeline
            viewModel.icon = "checkmark.circle.fill"
            viewModel.iconColor = .green
            viewModel.iconAnimation = .pulsing
            viewModel.title = "Pushed #\(issueNumber)"
            viewModel.subtitle = repoFullName
            viewModel.issueURL = issueURL
            viewModel.projectName = projectName
            viewModel.projectURL = projectURL
            viewModel.projectFailed = projectFailed
            viewModel.isV2Project = isV2

        case .error(let message):
            viewModel.mode = .pipeline
            viewModel.icon = "xmark.circle.fill"
            viewModel.iconColor = .red
            viewModel.iconAnimation = .none
            viewModel.title = "Failed"
            viewModel.subtitle = message
            resetPipelineExtras()
        }

        presentIfNeeded()
        Task { @MainActor [weak self] in
            guard let self, let notch = self.notch, let screen = NSScreen.main else { return }
            await notch.expand(on: screen)
        }

        switch state {
        case .confirmed:
            scheduleReturnToAmbient(after: Constants.islandConfirmDuration)
        case .error:
            scheduleReturnToAmbient(after: Constants.islandErrorDuration)
        default:
            break
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        returnToAmbientOrHide()
    }

    // MARK: - Private

    private func resetPipelineExtras() {
        viewModel.issueURL = nil
        viewModel.projectName = nil
        viewModel.projectURL = nil
        viewModel.projectFailed = false
        viewModel.isV2Project = false
    }

    /// Build the underlying DynamicNotch once. View content observes the shared
    /// NotchViewModel so mode switches happen purely through state changes.
    private func presentIfNeeded() {
        guard notch == nil else { return }
        let vm = viewModel
        let notch = DynamicNotch(
            hoverBehavior: [.hapticFeedback, .keepVisible],
            style: .notch,
            expanded: { NotchExpandedView(viewModel: vm) },
            compactLeading: { NotchCompactLeading(viewModel: vm) },
            compactTrailing: { NotchCompactTrailing(viewModel: vm) }
        )
        vm.kanbanOnExpand = { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let notch = self?.notch, let screen = NSScreen.main else { return }
                await notch.expand(on: screen)
            }
        }
        vm.kanbanOnDismiss = { [weak self] in
            guard let self else { return }
            self.returnToAmbientOrHide()
        }
        self.notch = notch

        Task { @MainActor in
            guard let screen = NSScreen.main else { return }
            if vm.mode == .kanban {
                await notch.compact(on: screen)
            } else {
                await notch.expand(on: screen)
            }
        }
    }

    private func scheduleReturnToAmbient(after delay: TimeInterval) {
        returnToCompactTask?.cancel()
        returnToCompactTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.returnToAmbientOrHide()
        }
    }

    private func returnToAmbientOrHide() {
        if ambientEnabled {
            viewModel.mode = .kanban
            Task { @MainActor [weak self] in
                guard let notch = self?.notch, let screen = NSScreen.main else { return }
                await notch.compact(on: screen)
            }
        } else {
            teardown()
        }
    }

    private func teardown() {
        let notch = self.notch
        self.notch = nil
        Task { @MainActor in
            await notch?.hide()
        }
    }
}

// MARK: - Expanded view (branches on mode)

struct NotchExpandedView: View {
    @Bindable var viewModel: NotchViewModel

    var body: some View {
        Group {
            switch viewModel.mode {
            case .pipeline:
                PipelineExpandedView(viewModel: viewModel)
            case .kanban:
                KanbanExpandedView(viewModel: viewModel)
            }
        }
    }
}

private struct PipelineExpandedView: View {
    @Bindable var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            AnimatedIcon(
                systemName: viewModel.icon,
                color: viewModel.iconColor,
                animation: viewModel.iconAnimation
            )
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                if !viewModel.subtitle.isEmpty {
                    Text(viewModel.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }

                if let projectName = viewModel.projectName {
                    ProjectBadge(
                        name: projectName,
                        urlString: viewModel.projectURL,
                        isV2: viewModel.isV2Project,
                        failed: viewModel.projectFailed
                    )
                }
            }

            Spacer(minLength: 0)

            if let urlString = viewModel.issueURL,
               let url = URL(string: urlString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("Open")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 40)
        .padding(.vertical, 4)
    }
}

// MARK: - Compact views

struct NotchCompactLeading: View {
    @Bindable var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.37, blue: 0.96))

            if let name = viewModel.kanbanProjectName ?? viewModel.kanbanBoard?.projectTitle, !name.isEmpty {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            } else {
                Text("No project")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.kanbanOnExpand?() }
    }
}

struct NotchCompactTrailing: View {
    @Bindable var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(Color(red: 0.18, green: 0.75, blue: 0.47))
            Text("\(viewModel.kanbanBoard?.totalOpenIssues ?? 0)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.kanbanOnExpand?() }
    }
}

// MARK: - ProjectBadge (unchanged)

struct ProjectBadge: View {
    let name: String
    let urlString: String?
    let isV2: Bool
    let failed: Bool

    private var badgeColor: Color {
        failed ? .orange : (isV2 ? Color(red: 0.47, green: 0.36, blue: 0.96) : .blue)
    }

    private var icon: String {
        failed ? "exclamationmark.triangle.fill" : (isV2 ? "sparkles" : "folder.fill")
    }

    private var label: String {
        failed ? "Failed: \(name)" : name
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(badgeColor)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(badgeColor.opacity(0.18))
                .overlay(Capsule().strokeBorder(badgeColor.opacity(0.4), lineWidth: 0.5))
        }
        .onTapGesture {
            if let urlString, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

struct AnimatedIcon: View {
    let systemName: String
    let color: Color
    let animation: IconAnimation

    var body: some View {
        AnimatedIconInner(systemName: systemName, color: color, animation: animation)
            .id(animation)
    }
}

private struct AnimatedIconInner: View {
    let systemName: String
    let color: Color
    let animation: IconAnimation

    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .onAppear {
                switch animation {
                case .rotating:
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                case .pulsing:
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        scale = 1.15
                    }
                case .none:
                    break
                }
            }
    }
}
