import SwiftUI

/// Canteiro › Settings: the Cloudflare account uploads use. Keys are stored
/// in the Keychain. The bucket and address are the site's, in its
/// canteiro.json, and only shown here.
struct SettingsView: View {
    @Environment(SiteStore.self) private var store
    @State private var accountID = R2Settings.accountID
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
                if let uploads = store.config.uploads {
                    LabeledContent("Bucket", value: uploads.bucket)
                    LabeledContent("Public address", value: uploads.publicBase)
                }
            } header: {
                Text("Cloudflare R2")
            } footer: {
                Text(store.config.uploads == nil
                     ? "\(store.siteName) has no uploads block in \(SiteConfig.fileName), so photo and MP3 drops are off."
                     : "The bucket and address come from \(store.siteName)'s \(SiteConfig.fileName).")
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
        R2Settings.accessKeyID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        R2Settings.secretAccessKey = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        status = .checking
        Task {
            do {
                guard let bucket = store.config.uploads?.bucket else { throw SiteStore.UploadFailure.noUploads }
                try await R2Client.fromSettings(bucket: bucket).check()
                status = .ok
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}
