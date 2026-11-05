import SwiftUI

struct AccountsView: View {
    @State private var gitlab = Accounts.gitlab ?? GitLabAccount(url: "", token: "")
    @State private var gitlabResult: String?
    @State private var google = Accounts.googleChat ?? GoogleChatAccount(clientID: "", clientSecret: "")
    @State private var googleResult: String?
    @State private var connecting: Task<Void, Never>?
    @State private var checking = false

    var body: some View {
        Form {
            Section {
                TextField("Instanz-URL", text: $gitlab.url, prompt: Text("https://gitlab.com"))
                SecureField("Access Token", text: $gitlab.token)
                actions(result: gitlabResult, canSave: !gitlab.url.isEmpty && !gitlab.token.isEmpty) {
                    Accounts.save(gitlab)
                    await check(gitlab: gitlab)
                } onRemove: {
                    Accounts.save(nil as GitLabAccount?)
                    gitlab = GitLabAccount(url: "", token: "")
                    gitlabResult = nil
                }
            } header: {
                Text("GitLab")
            } footer: {
                Text("Ein Personal Access Token mit dem Bereich read_api reicht. Das Widget zeigt die letzte Pipeline deiner aktiven Projekte und deine offenen Merge Requests.")
            }

            Section {
                Group {
                    TextField("Client-ID", text: $google.clientID, prompt: Text(verbatim: "…apps.googleusercontent.com"))
                    SecureField("Client-Secret", text: $google.clientSecret)
                }
                .disabled(connecting != nil)
                googleActions
            } header: {
                Text("Google Chat")
            } footer: {
                Text("In der Google Cloud Console die Google Chat API aktivieren und einen OAuth-Client vom Typ „Desktop-App“ anlegen. „Mit Google verbinden“ öffnet den Browser, die Antwort fängt die Bridge lokal auf 127.0.0.1 ab. Das Widget zeigt ungelesene Nachrichten; ihre Texte bleiben nur im Speicher.")
            }

            Section {
                Label("Tokens liegen im macOS-Schlüsselbund und verlassen den Mac nie. Das iPhone bekommt nur Tickets, Pipelines und ungelesene Chat-Nachrichten.", systemImage: "lock")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Konten")
        .disabled(checking)
    }

    private func actions(result: String?, canSave: Bool, onSave: @escaping () async -> Void, onRemove: @escaping () -> Void) -> some View {
        HStack {
            if let result {
                Text(result)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Entfernen", role: .destructive, action: onRemove)
            Button("Sichern und prüfen") {
                Task {
                    checking = true
                    await onSave()
                    checking = false
                }
            }
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var googleActions: some View {
        HStack {
            if connecting != nil {
                ProgressView()
                    .controlSize(.small)
            }
            Text(googleStatus)
                .foregroundStyle(.secondary)
            Spacer()
            if let connecting {
                Button("Abbrechen") { connecting.cancel() }
            } else {
                Button("Trennen", role: .destructive) { disconnectGoogle() }
                    .disabled(!google.isConnected)
                Button(google.isConnected ? "Neu verbinden" : "Mit Google verbinden") { connectGoogle() }
                    .disabled(google.clientID.trimmingCharacters(in: .whitespaces).isEmpty || google.clientSecret.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var googleStatus: String {
        if let googleResult { return googleResult }
        if connecting != nil { return String(localized: "Im Browser bei Google anmelden …") }
        return google.isConnected ? String(localized: "Verbunden als \(google.email ?? String(localized: "Google-Konto"))") : String(localized: "Nicht verbunden")
    }

    private func connectGoogle() {
        let clientID = google.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = google.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = google.email
        googleResult = nil
        connecting = Task {
            do {
                let account = try await GoogleAuth.connect(clientID: clientID, clientSecret: secret, hint: hint)
                Accounts.save(account)
                google = account
                googleResult = String(localized: "Verbunden als \(account.email ?? String(localized: "Google-Konto")) · lese Postfach …")
                await check(google: account)
            } catch {
                googleResult = (error as? GoogleChatError ?? .unreachable).message
            }
            connecting = nil
        }
    }

    private func disconnectGoogle() {
        if let token = google.refreshToken {
            Task { await GoogleAuth.revoke(token) }
        }
        google.refreshToken = nil
        google.email = nil
        google.userID = nil
        Accounts.save(google)
        googleResult = nil
    }

    private func check(google account: GoogleChatAccount) async {
        let payload = await GoogleChatClient.cachedReport(account: account)
        let unread = payload["unread"] as? Int ?? 0
        googleResult = payload["error"] as? String ?? String(localized: "Verbunden als \(account.email ?? String(localized: "Google-Konto")) · \(unread) ungelesen")
    }

    private func check(gitlab account: GitLabAccount) async {
        let payload = await GitLabClient.cachedReport(account: account)
        gitlabResult = payload["error"] as? String ?? String(localized: "Verbunden · \((payload["pipelines"] as? [JSON])?.count ?? 0) Projekte")
    }
}
