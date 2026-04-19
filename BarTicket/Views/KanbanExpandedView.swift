import SwiftUI
import AppKit

struct KanbanExpandedView: View {
    @Bindable var viewModel: NotchViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let board = viewModel.kanbanBoard {
                BoardContent(
                    board: board,
                    onCardCopied: viewModel.kanbanOnCardCopied
                )
            } else if let error = viewModel.kanbanFetchError {
                ErrorState(message: error) {
                    viewModel.kanbanOnSelectProject?()
                }
            } else if viewModel.kanbanProjectName != nil {
                LoadingState()
            } else {
                EmptyState {
                    viewModel.kanbanOnSelectProject?()
                }
            }

            HStack(spacing: 6) {
                Button {
                    viewModel.kanbanOnRefresh?()
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.kanbanOnDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
    }
}

// MARK: - Board

private struct BoardContent: View {
    let board: KanbanBoard
    let onCardCopied: ((KanbanCard) -> Void)?

    // DynamicNotchKit sizes the panel to screen.width / 2, with ~60pt consumed by
    // safe-area insets and corner-radius padding. Cap board width accordingly so
    // content never overflows the panel on smaller screens (e.g. 13" MBA = 640pt panel).
    private var boardWidth: CGFloat {
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        return min(760, (screenWidth / 2) - 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group.fill")
                    .foregroundStyle(Color(red: 0.55, green: 0.37, blue: 0.96))

                Text(board.projectTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = URL(string: board.projectURL) {
                    NSWorkspace.shared.open(url)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(board.columns) { column in
                        ColumnView(column: column, onCardCopied: onCardCopied)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .frame(width: boardWidth, height: 360)
    }
}

private struct ColumnView: View {
    let column: KanbanColumn
    let onCardCopied: ((KanbanCard) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(column.color)
                    .frame(width: 8, height: 8)
                
                Text(column.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text("\(column.cards.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(column.color.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(column.color.opacity(0.4), lineWidth: 0.5)
                    )
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(column.cards) { card in
                        CardView(card: card, accent: column.color, onCardCopied: onCardCopied)
                    }
                    if column.cards.isEmpty {
                        Text("Empty")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.vertical, 12)
                    }
                }
            }
        }
        .frame(width: 200)
    }
}

private struct CardView: View {
    let card: KanbanCard
    let accent: Color
    let onCardCopied: ((KanbanCard) -> Void)?

    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(card: card, accent: accent)
            if !card.labels.isEmpty {
                CardLabels(labels: card.labels)
            }
            if justCopied {
                CopiedIndicator()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    private func handleTap() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.body, forType: .string)
        onCardCopied?(card)
        withAnimation(.easeOut(duration: 0.2)) { justCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) { justCopied = false }
            }
        }
    }
}

private struct CardHeader: View {
    let card: KanbanCard
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("#\(card.issueNumber)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)

            Text(card.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let url = URL(string: card.issueURL) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(4)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CardLabels: View {
    let labels: [KanbanLabel]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(labels.prefix(3), id: \.name) { label in
                Text(label.name)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(label.color.opacity(0.85)))
            }
            if labels.count > 3 {
                Text("+\(labels.count - 3)")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

private struct CopiedIndicator: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.green)
            Text("Copied")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Empty / Loading / Error

private struct EmptyState: View {
    let onSelectProject: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.3.group.bubble.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color(red: 0.55, green: 0.37, blue: 0.96))

            Text("No Kanban project selected")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Pick a GitHub Projects v2 board to see your work at a glance.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button(action: onSelectProject) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Select a Project")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color(red: 0.55, green: 0.37, blue: 0.96))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(width: 420, height: 220)
    }
}

private struct LoadingState: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text("Loading board…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(24)
        .frame(width: 420, height: 180)
    }
}

private struct ErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text("Couldn't load board")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Retry", action: onRetry)
                .font(.system(size: 11))
        }
        .padding(20)
        .frame(width: 420, height: 200)
    }
}
