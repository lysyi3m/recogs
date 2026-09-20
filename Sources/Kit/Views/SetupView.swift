import SwiftUI

/// Minimal token entry, standing in until step 7 builds the real first-run flow.
struct SetupView: View {
    @Environment(AppServices.self) private var services

    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Personal Access Token") {
                SecureField("Paste your Discogs token", text: $token)
                Button("Validate and Save", action: validate)
                    .disabled(token.isEmpty || isValidating)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private func validate() {
        isValidating = true
        errorMessage = nil
        Task {
            do {
                try await services.signIn(token: token)
                token = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isValidating = false
        }
    }
}
