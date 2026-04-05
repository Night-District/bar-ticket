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
}

@MainActor
final class DynamicIslandController {
    private var notch: DynamicNotch<NotchExpandedView, EmptyView, EmptyView>?
    private let viewModel = NotchViewModel()
    private var dismissTask: Task<Void, Never>?
    private var isVisible = false

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

        case .creating(let title):
            viewModel.icon = "arrow.trianglehead.2.counterclockwise"
            viewModel.iconColor = .orange
            viewModel.iconAnimation = .rotating
            viewModel.title = "Creating issue..."
            viewModel.subtitle = title
            viewModel.issueURL = nil

        case .confirmed(_, let repoFullName, let issueNumber, let issueURL):
            viewModel.icon = "checkmark.circle.fill"
            viewModel.iconColor = .green
            viewModel.iconAnimation = .pulsing
            viewModel.title = "Pushed #\(issueNumber)"
            viewModel.subtitle = repoFullName
            viewModel.issueURL = issueURL

        case .error(let message):
            viewModel.icon = "xmark.circle.fill"
            viewModel.iconColor = .red
            viewModel.iconAnimation = .none
            viewModel.title = "Failed"
            viewModel.subtitle = message
            viewModel.issueURL = nil
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

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                if !viewModel.subtitle.isEmpty {
                    Text(viewModel.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
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
        .frame(height: 40)
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
