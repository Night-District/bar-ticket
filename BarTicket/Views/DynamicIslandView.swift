import SwiftUI

/// ViewModel bridging IslandState to the SwiftUI view
@Observable
@MainActor
final class DynamicIslandViewModel {
    var state: IslandState = .hidden
    var onClickURL: ((String) -> Void)?

    func update(state: IslandState) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            self.state = state
        }
    }
}

struct DynamicIslandView: View {
    @Bindable var viewModel: DynamicIslandViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .hidden:
                Color.clear
                    .frame(width: 0, height: 0)

                //TODO: Add a subtle "bar ticket" icon in the corner when idle?
                
                // TODO: Maybe show a "no TODOs detected" message after some idle time?
                
                //TODO: sfdsdfdsdsfsdffd hey
                
                
                
            case .detecting(let title):
                islandPill {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.blue)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("TODO detected")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("— \(title)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .transition(.scale(scale: 0.3).combined(with: .opacity))

            case .creating(let title):
                islandPill {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.orange)
                        Text("Creating issue...")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("— \(title)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))

            case .confirmed(_, let repoFullName, let issueNumber, let issueURL):
                islandPill {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: issueNumber)
                        Text("Pushed")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("#\(issueNumber)")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(.green)
                        Text("to \(repoFullName)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .onTapGesture {
                        viewModel.onClickURL?(issueURL)
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))

            case .error(let message):
                islandPill {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: viewModel.state)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func islandPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.black.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            )
    }
}
