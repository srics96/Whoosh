# Blink

**Switch agents. Keep your flow.**

**Mac validation update:** The native release builds and supports compact Codex and local Claude Code pickers with remembered connections. Claude Desktop Code metadata and a selected synthetic session were read through the official SDK. Synthetic Claude → Codex staging preserved 36 API messages and requested a native draft; Codex UI inspection is denied, so draft display/receipt remain unverified. Codex → Claude draft population was verified, but its explicit synthetic test submission remains stuck at Claude’s “Starting session”. XCTest is absent; native smoke checks are separate. See `docs/MAC_RESULT.md`.

Source repository: [srics96/blink](https://github.com/srics96/blink).

A native macOS handoff companion prototype. Press a global shortcut, choose a source conversation, prepare a checkpoint, and review what will move before opening the destination app.

**Blink is a provisional project name. This is a source prototype, not a signed production release.** It does not pretend to migrate native chat databases or prove that the destination has loaded your history.

## What it does

- Menu-bar companion and a compact SwiftUI handoff window.
- Registered global hotkey, without keylogging or an Accessibility event tap.
- Foreground-app suggestion, not a claim to know the selected conversation.
- Optional read-only Codex app-server session picker using an automatically detected, signature-verified CLI after one-time connection consent. Connection is opt-in and capability-gated.
- Reliable fallback: choose one exported `.txt`, `.md`, or `.json` file. Its original bytes are saved unchanged, with byte count, optional UTF-8 character count, and SHA-256.
- A deterministic checkpoint from the selected title/history, with an optional user instruction. Unknown decisions and verification are explicitly marked unknown.
- Read-only Git **branch, commit, and repository-root metadata**. Worktree status and diffs are intentionally unavailable because even `git status` can invoke repository-defined clean filters.
- A private handoff package in ~/Library/Application Support/Blink/Handoffs, outside the source repository. No existing source repository files or original app database are changed.
- Claude desktop draft request using the documented short bootstrap URL. Workspace trust/file access remain provider confirmations; actual receipt is verified separately.
- Codex destination requests a new composer through the documented codex://threads/new route with encoded prompt/path. Blink never submits a turn or claims the destination read its files.
- A restrained transition animation with Reduce Motion support. Completion means the destination-open request succeeded, not that an agent read or understood the archive.

## Current capability boundaries

| Capability | Status |
| --- | --- |
| Preserve selected export bytes | Implemented, SHA-256 checked after writing |
| Select a Codex source thread | Experimental documented API adapter, Mac compatibility still needs validation |
| Automatically identify the foreground app's selected thread | Not supported |
| Read the entire native conversation including hidden/internal state | Not supported |
| Open Claude with context | Draft route implemented; fresh receipt check awaits workspace trust |
| Attach archive through the Claude Code URL | Not supported by Claude's documented Code link |
| Automatically submit a prompt | Deliberately never supported |
| Reverse handoff into Codex native context | Documented new-draft route; installed composer display awaiting confirmation |
| Stop or verify the source agent | User confirmation only, not process verification |
| Transfer permissions, runtime, quota, model state, or hidden reasoning | Not supported |
| Live Codex account rate-limit read | Optional provider capability; UI may report unknown when not connected or unsupported |
| Claude usage/quota | Unknown; no fabricated progress bars |

## Build on macOS

Requirements: macOS 13 or later and an existing Swift 5.9+ toolchain (Xcode 15+ Command Line Tools). No package dependencies are downloaded.

```sh
swift test
swift build
bash scripts/build-app.sh
```

The packaging script runs the tests, builds a release executable, creates `dist/Blink.app`, and ad-hoc signs it for local testing. It does not install, launch, upload, or notarize the app. Open the resulting bundle manually when ready:

```sh
open dist/Blink.app
```

The app is a menu-bar accessory. Its menu offers the handoff window and shortcut settings. A shortcut conflict must be shown as an error, not silently treated as registration success.

For development, `swift run Blink` can launch the executable, but the `.app` bundle is the preferred test target for native window/menu behavior.

## Cloud checks versus Mac validation

```sh
bash scripts/check.sh
```

The portable Python checks inspect source contracts, exercise a URL-encoding reference, verify binary preservation assumptions, and test real Git metadata commands against a temporary synthetic repository with a hostile clean-filter fixture. **They do not compile or execute Swift.** The cloud authoring environment has no Swift toolchain; `swift test`, AppKit/SwiftUI compilation, global-hotkey registration, UI accessibility, and installed-app deep-link behavior remain separate Mac gates.

`Tests/RelayCoreTests` contains the actual Swift tests for SHA-256 known vectors, Unicode/reserved URL characters, conservative prompt limits, raw byte preservation, invalid UTF-8, private file modes, no overwrite, pre-write validation, read-only Git metadata, and native-provider protocol contracts.

Use [`docs/MAC_VALIDATION.md`](docs/MAC_VALIDATION.md) for the local verification checklist. Use only synthetic fixtures until explicitly choosing a real conversation.

## Privacy and safety model

1. Source access starts with a chosen file or an explicit Connect action. Blink does not scan home/session directories, read credentials, scrape app databases, or access the clipboard in the background.
2. The selected source archive is kept local. Its contents are not embedded wholesale into a URL. The bootstrap names the local archive and instructs the destination to treat historical material as untrusted data, not new authorization.
3. The bootstrap itself includes the user-entered checkpoint and local paths. Review it before opening another app. Once you submit in that app, its own privacy/data-processing policies apply.
4. The native source archive preserves exact fetched API response bytes. It is not a claim of original-native-store preservation, may be partial, and may include private tool data beyond the text-only preview.
5. Handoff directories are created with mode `0700`, files with `0600`. The default parent is app-controlled Application Support; symlink-redirection is rejected. Local backups and permissions beyond POSIX modes are outside Blink’s guarantees.
6. No shell is used for runtime subprocesses. Git is restricted to metadata reads; no status, diff, commits, stashes, resets, hooks, or content filters are requested.
7. Codex CLI requests are allowlisted and bounded. Unsupported safe-list capabilities fail closed instead of falling back to scanning or repairing native logs.
8. Launch requires a reviewed package, a user attestation that the source agent is stopped, and explicit approval to pass the visible bootstrap to the destination. Blink cannot prove the source has stopped.

## Package format

Each new handoff gets a unique directory and never overwrites an earlier package:

```text
Blink-<timestamp>-<random>/
  transcript/original.<ext>  # Exact selected bytes, no normalization
  manifest.json             # Origin, byte/hash evidence, checkpoint, Git metadata, limits
  CHECKPOINT.md             # Human-readable state and explicit omissions
  bootstrap.txt             # Full reviewed bootstrap, never silently truncated
  README.txt                # Local package handling and privacy notes
```

The prompt budget is 12,000 UTF-16 units, deliberately below Claude's approximate 14,000-character truncation point. Too-long checkpoints are rejected before any package is written. The archive itself is not truncated; selected imports are bounded to 64 MiB and native source retrieval has a smaller explicit limit.

## Architecture

- `RelayCore`: portable Foundation models, raw archives, SHA-256, prompt encoding, metadata-only Git capture.
- `RelayCore/Providers`: isolated read-only Codex JSON-RPC source adapter and bounded stdio transport.
- `RelayApp`: macOS SwiftUI/AppKit UI, menu-bar lifecycle, Carbon hotkey registration, source selection/review, native app detection and launch.
- `Tests/RelayCoreTests`: executable Swift tests with synthetic data.
- `scripts`: cloud contract checks and local `.app` packaging.

The source-provider boundary is intentional. The Claude adapter uses only the official SDK read APIs for local Code sessions. Chat/Cowork coverage, full original-log preservation and Codex destination receipt are not established. See [`docs/native-source.md`](docs/native-source.md).

## Official protocol references

- [Claude Desktop deep links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link): `claude://code/new`, URL-encoded `q` and `folder`, prefill only, folder confirmation, Code `file` parameter currently unsupported.
- [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server): capability-gated source adapter; exact supported behavior depends on the user-selected installed CLI.

No third-party account credentials, exports, conversations, generated handoff packages, or private project content belong in this public source repository. All fixtures here are synthetic.

The compact flow is: approve Connect Codex once (its signed helper is then revalidated and reconnected on restart), search/select a chat, optionally add an instruction, confirm the source is stopped, review, approve the data boundary, then open the destination. Import, paths and checkpoint edits are under Advanced. A missing actual project folder triggers a folder chooser; no invented project path is used. A conservative local credential/card screen blocks detected matches; it is not an exhaustive PII detector, and user privacy review remains required.

[Codex desktop commands and links](https://learn.chatgpt.com/docs/reference/commands) documents the new-draft route.

## Latest tiny-switcher iteration

The newest unopened bundle is `dist-next/Blink.app` (440×400). Select a chat and use the clearly labeled Continue action; its inline disclosure is the per-handoff boundary confirmation. Known-idle API status is rechecked automatically; unknown source activity still requires explicit confirmation. Optional instructions and full technical details are behind disclosure controls. No destination submission is automated. The original Blink vector is `Resources/Blink.svg`; provider icons are read from verified installed apps at runtime and are not bundled. Build and core checks pass; new visual behavior awaits post-demo validation.


### Optional local Claude Code runtime

The Mac build uses the user-approved `@anthropic-ai/claude-agent-sdk@0.3.306`, installed with `--ignore-scripts --omit=optional` in a separate adapter folder. Dependency manifests are preserved in `Resources/ClaudeAdapter/`; no dependency binaries or private histories are in the source ZIP. `scripts/configure-claude-adapter.py APP NODE SDK_MODULE` packages an already-installed SDK into the local app and records its existing Node runtime. It never installs anything. Set `BLINK_CLAUDE_SDK_MODULE` and `BLINK_NODE` for the normal build script to include it; obtain approval before any new installation.

The app lists metadata only until a chat is selected. The selected API chain includes exposed user/assistant/system and tool content, but is explicitly partial relative to original logs: branches, subagents and attachment file bytes are not collected. Source activity is unknown, so confirmation that it is stopped remains necessary. The existing local SDK installation and packaged app must remain available; moving the app between machines is not a supported installer flow.
