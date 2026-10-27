import SwiftUI

struct AccountsView: View {
    @State private var orbit = Accounts.orbit ?? OrbitAccount(apiURL: "", webURL: "", token: "")
    @State private var gitlab = Accounts.gitlab ?? GitLabAccount(url: "", token: "")
    @State private var orbitResult: String?
    @State private var gitlabResult: String?
    @State private var checking = false

    private static var showsOrbit: Bool {
        UserDefaults.standard.bool(forKey: "showsOrbit") || Accounts.orbit != nil
    }

    var body: some View {
        Form {
            if Self.showsOrbit {
                Section {
                    TextField("API-URL", text: $orbit.apiURL, prompt: Text("https://orbit.example.com"))
                    TextField("Web-URL", text: $orbit.webURL, prompt: Text("wie API-URL"))
                    SecureField("Personal Access Token", text: $orbit.token)
                    actions(result: orbitResult, canSave: !orbit.apiURL.isEmpty && !orbit.token.isEmpty) {
                        Accounts.save(orbit)
                        await check(orbit: orbit)
                    } onRemove: {
                        Accounts.save(nil as OrbitAccount?)
                        orbit = OrbitAccount(apiURL: "", webURL: "", token: "")
                        orbitResult = nil
                    }
                } header: {
                    Text("Orbit")
                } footer: {
                    Text("Den Token legst du in Orbit unter Konto → Einstellungen → Personal Access Tokens an. Das Widget zeigt deine offenen Tickets.")
                }
            }

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
                Label("Tokens liegen im macOS-Schlüsselbund und verlassen den Mac nie. Das iPhone bekommt nur die Ticket- und Pipeline-Liste.", systemImage: "lock")
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

    private func check(orbit account: OrbitAccount) async {
        let payload = await OrbitClient.cachedReport(account: account)
        orbitResult = payload["error"] as? String ?? "Verbunden · \((payload["issues"] as? [JSON])?.count ?? 0) offene Tickets"
    }

    private func check(gitlab account: GitLabAccount) async {
        let payload = await GitLabClient.cachedReport(account: account)
        gitlabResult = payload["error"] as? String ?? "Verbunden · \((payload["pipelines"] as? [JSON])?.count ?? 0) Projekte"
    }
}
