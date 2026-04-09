import AppKit
import SwiftUI
import DynamicNotchKit

enum IconAnimation: Equatable {
    case none
    case rotating
    case pulsing
}

@MainActor
@Observable
final class NotchViewModel {
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
}

@MainActor
final class DynamicIslandController {
    private var notch: DynamicNotch<NotchExpandedView, EmptyView, EmptyView>?
    private let viewModel = NotchViewModel()
    private var dismissTask: Task<Void, Never>?
    private var isVisible = false
    
    //TODO: design/github-icons (#59 https://github.com/Night-District/bar-ticket/issues/59)
    // Download actual GitHub icon SVGs for projects, issues, branches, etc. and render them in the island instead of generic system icons.
    func show(state: IslandState) {
        dismissTask?.cancel()
        
        switch state {
        case .hidden:
            dismiss()
            return
        
        case .detecting(let title):
            viewModel.icon = "gear"
            viewModel.iconColor = .blue
            viewModel.iconAnimation = .rotating
            viewModel.title = "TODO detected"
            viewModel.subtitle = title
            viewModel.issueURL = nil
            viewModel.projectName = nil
            viewModel.projectURL = nil
            viewModel.projectFailed = false
            viewModel.isV2Project = false

        case .creating(let title):
            viewModel.icon = "arrow.trianglehead.2.counterclockwise"
            viewModel.iconColor = .orange
            viewModel.iconAnimation = .rotating
            viewModel.title = "Creating issue..."
            viewModel.subtitle = title
            viewModel.issueURL = nil
            viewModel.projectName = nil
            viewModel.projectURL = nil
            viewModel.projectFailed = false
            viewModel.isV2Project = false

        case .updating(let title):
            viewModel.icon = "arrow.trianglehead.clockwise"
            viewModel.iconColor = .cyan
            viewModel.iconAnimation = .rotating
            viewModel.title = "Updating issue..."
            viewModel.subtitle = title
            viewModel.issueURL = nil
            viewModel.projectName = nil
            viewModel.projectURL = nil
            viewModel.projectFailed = false
            viewModel.isV2Project = false

        case .confirmed(_, let repoFullName, let issueNumber, let issueURL, let projectName, let projectURL, let projectFailed, let isV2):
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
            viewModel.icon = "xmark.circle.fill"
            viewModel.iconColor = .red
            viewModel.iconAnimation = .none
            viewModel.title = "Failed"
            viewModel.subtitle = message
            viewModel.issueURL = nil
            viewModel.projectName = nil
            viewModel.projectURL = nil
            viewModel.projectFailed = false
            viewModel.isV2Project = false
        }

        if !isVisible {
            isVisible = true
            let newNotch = DynamicNotch(hoverBehavior: [.hapticFeedback], style: .notch) {
                NotchExpandedView(viewModel: self.viewModel)
            }
            notch = newNotch
            Task { @MainActor in
                if let screen = NSScreen.main {
                    await newNotch.expand(on: screen)
                }
            }
        }

        switch state {
        case .confirmed:
            scheduleDismiss(after: Constants.islandConfirmDuration)
        case .error:
            scheduleDismiss(after: Constants.islandErrorDuration)
        default:
            break
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        isVisible = false
        Task { @MainActor in
            await notch?.hide()
            notch = nil
        }
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            isVisible = false
            await notch?.hide()
            notch = nil
        }
    }
}

//TODO: refactor/NotchExpandedView (#80 https://github.com/Night-District/bar-ticket/issues/80)
// Refactor the NotchExpandedView to be more modular and reusable. For example, create separate subviews for the icon, text, and project badge sections. This will make it easier to maintain and extend in the future as we add more features or different types of notifications.
struct NotchExpandedView: View {
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

            //TODO: i dont like this (#81 https://github.com/Night-District/bar-ticket/issues/81)
            // Remove this hacky spacer once we have a better layout solution for the island content. Right now it just pushes the Open button to the right edge, but ideally we'd want a more flexible layout that can adapt to different content lengths and screen sizes without needing invisible spacers.
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

// MARK: - ProjectBadge

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
