import DiscogsKit
import SwiftUI

/// First run: take a Personal Access Token, prove it works against `/oauth/identity`, store it in
/// the Keychain, then hand off to the initial sync.
///
/// The token is the only thing standing between a fresh install and a working collection, so the
/// screen explains where to get one rather than just presenting an empty field.
struct SetupView: View {
    /// Called once a token has been validated and saved, so the collection can do its first sync.
    var onSignedIn: () -> Void = {}

    @Environment(AppServices.self) private var services

    @State private var token = ""
    @State private var state: State = .idle

    private enum State: Equatable {
        case idle
        case validating
        case failed(String)
    }

    private static let tokenSettingsURL = URL(string: "https://www.discogs.com/settings/developers")!

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "record.circle")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    Text("Welcome to Recogs")
                        .font(.title.weight(.semibold))
                    Text("Your Discogs collection, on this device.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Paste a Personal Access Token to connect. It is stored in the Keychain on this device and never sent anywhere but Discogs.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: Self.tokenSettingsURL) {
                        Label("Generate a token on Discogs", systemImage: "arrow.up.right.square")
                            .font(.callout)
                    }
                }

                VStack(spacing: 10) {
                    SecureField("Personal Access Token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { validate() }
                        #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        #endif

                    Button {
                        validate()
                    } label: {
                        if isValidating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Connect")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedToken.isEmpty || isValidating)
                }

                if case .failed(let message) = state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(28)
        }
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidating: Bool { state == .validating }

    private func validate() {
        guard !trimmedToken.isEmpty else { return }
        state = .validating
        Task {
            do {
                try await services.signIn(token: trimmedToken)
                token = ""
                state = .idle
                onSignedIn()
            } catch {
                state = .failed(message(for: error))
            }
        }
    }

    /// A rejected token and an unreachable network look the same in a raw error string, and the
    /// fix for each is different.
    private func message(for error: any Error) -> String {
        guard let discogsError = error as? DiscogsError else { return error.localizedDescription }
        if discogsError.isUnauthorized {
            return "Discogs did not accept that token. Check you copied all of it, and that it has not been revoked."
        }
        if discogsError.isOffline {
            return "No connection to Discogs. Check your network and try again."
        }
        return discogsError.localizedDescription
    }
}
