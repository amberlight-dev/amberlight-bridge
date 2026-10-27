# Amberlight Bridge

The Mac menu bar app behind [Amberlight](https://amberlight.dev): it shows your Claude Code and Codex sessions on an iPhone next to your screen, as working, waiting for you or done. Tap a session on the phone and its terminal comes to the front. Approve prompts and answer questions from the phone.

The Bridge is open source because it is the part that reads your files and drives your windows. The iPhone app is free on the App Store.

## Install

- **DMG:** [amberlight.dev/mac](https://amberlight.dev/mac/). Signed with Developer ID, notarized by Apple, updates itself via [Sparkle](https://sparkle-project.org).
- **Homebrew:** `brew install --cask amberlight-dev/tap/amberlight-bridge`

macOS 15 or later. Then install [Amberlight](https://amberlight.dev) on your iPhone and scan the QR code from the menu bar.

## What it reads and writes

| What | Where | Why |
|---|---|---|
| Hooks for Claude Code | `~/.claude/settings.json` | Claude Code reports session events (prompt submitted, permission request, question, stop) to the Bridge. Installed and removed by you under **Diagnose**. |
| Status line for Claude Code | `~/.claude/settings.json`, writes `~/.claude/stand-usage.json` | Usage and limits for the usage widget. Optional, set up under **Diagnose**. |
| Hooks for Codex | `~/.codex/hooks.json`, reads `~/.codex/sessions` | Same as above, for Codex. Installed and removed by you. |
| Pairing token | `~/.config/duo-stand/token` | Every hook call and every request from the iPhone must carry it. |
| Layout and custom widgets | `~/Library/Application Support/Stand Bridge/` | What your iPhone shows. |
| Accounts (GitLab, custom widgets) | Keychain | Only if you add them. |

The hooks are `curl` calls to `http://127.0.0.1:7420/hook` with the token in a header. You can read them in [`ClaudeSettings.swift`](StandBridge/ClaudeSettings.swift) and [`CodexSettings.swift`](StandBridge/CodexSettings.swift).

## What goes over the network

| From | To | What |
|---|---|---|
| iPhone | Your Mac, local network only | Sessions, questions, answers, usage, layout. Found via Bonjour (`_duostand._tcp`), port 7420, token from the QR pairing. |
| Bridge | amberlight.dev | The Sparkle appcast, to check for updates. Can be turned off under **Diagnose → Mac**. |
| Bridge | Services you configure | GitLab pipelines and custom widgets fetch the URLs you enter. |
| Bridge | lab73 | Nothing. No account, no analytics, no telemetry. |

## Permissions

- **Local network:** so your iPhone can reach the Bridge.
- **Automation (Apple Events):** to bring the terminal window of a session to the front when you tap it.
- **Accessibility:** only for "send answers directly", which pastes your answer into the terminal and presses Return.

## Build from source

Requirements: Xcode 26.2 or later.

```bash
git clone https://github.com/amberlight-dev/amberlight-bridge.git
cd amberlight-bridge
xcodebuild -project AmberlightBridge.xcodeproj -scheme StandBridge build
```

To run it signed on your own Mac, open the project in Xcode and set your own team under *Signing & Capabilities* (the project uses lab73's team `2JQL7NUGQB`). Tests:

```bash
xcodebuild -project AmberlightBridge.xcodeproj -scheme StandBridge test
```

The code in `Shared/` (layout, widget and mascot models and views) is also compiled into the iPhone app, which is closed source. The UI of the Bridge is in German for now.

## Verify a download

```bash
spctl -a -vv "/Applications/Amberlight Bridge.app"
```

Expected: `accepted`, `source=Notarized Developer ID`, `origin=Developer ID Application: lab73 GmbH (2JQL7NUGQB)`.

## Contributing

Issues and pull requests are welcome. For ideas and votes on what comes next, use the [feedback board](https://amberlight.fider.io). Security problems: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE), © 2026 lab73 GmbH.

Amberlight is an independent app by lab73 GmbH. It is not affiliated with, endorsed by or sponsored by Anthropic, PBC or OpenAI. Claude and Claude Code are trademarks of Anthropic, PBC, Codex is a trademark of OpenAI; they are named here only to describe compatibility.
