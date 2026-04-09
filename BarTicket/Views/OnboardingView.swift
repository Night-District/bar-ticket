import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("Welcome to Bar Ticket")
                        .font(.title3.bold())

                    Text("Connect your GitHub account to start creating issues automatically from your TODO comments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    Button {
                        appState.authService.startOAuthFlow()
                    } label: {
                        HStack(spacing: 8) {
                            if appState.authService.isExchangingToken {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Connecting...")
                            } else {
                                Image(systemName: "person.badge.key.fill")
                                Text("Sign in with GitHub")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.authService.isExchangingToken)

                    if let error = appState.authService.error {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            // Footer
            HStack {
                Button("Quit Bar Ticket") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.horizontal)
    }
}
