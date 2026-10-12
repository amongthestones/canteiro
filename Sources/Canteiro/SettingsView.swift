import SwiftUI

/// Canteiro › Settings: where uploads go. Keys are stored in the Keychain.
struct SettingsView: View {
    @State private var accountID = R2Settings.accountID
    @State private var bucket = R2Settings.bucket
    @State private var publicBase = R2Settings.publicBase
    @State private var accessKeyID = R2Settings.accessKeyID
    @State private var secret = R2Settings.secretAccessKey
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle, checking, ok
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("Account ID", text: $accountID, prompt: Text("From the R2 overview page"))
                TextField("Bucket", text: $bucket)
                TextField("Public address", text: $publicBase)
            } header: {
                Text("Cloudflare R2")
            } footer: {
                Text("Photos go to uploads/YYYY/MM/ and episodes to podcasts/<show>/. Links use the public address.")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Access key ID", text: $accessKeyID)
                SecureField("Secret access key", text: $secret)
            } header: {
                Text("API token")
            } footer: {
                Text("An R2 API token with Object Read & Write on this bucket. Kept in your Keychain.")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    switch status {
                    case .idle: EmptyView()
                    case .checking: ProgressView().controlSize(.small)
                    case .ok: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Save and Check") { saveAndCheck() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func saveAndCheck() {
        R2Settings.accountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        R2Settings.bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        R2Settings.publicBase = publicBase.trimmingCharacters(in: .whitespacesAndNewlines)
        R2Settings.accessKeyID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        R2Settings.secretAccessKey = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        status = .checking
        Task {
            do {
                try await R2Client.fromSettings().check()
                status = .ok
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}
