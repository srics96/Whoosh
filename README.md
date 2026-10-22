# Whoosh

**Switch agents. Keep your flow.**

Whoosh is a native macOS menu-bar companion that moves a coding conversation
between **Claude Code** and **Codex** in one keystroke. Press a global shortcut,
pick the chat, hit Return — and the other app opens with your context already in
the composer, ready to continue.

Source repository: [srics96/blink](https://github.com/srics96/blink).

> Whoosh is a source prototype, not a signed production release. It does not
> migrate native chat databases, and it never submits a turn for you — it opens a
> pre-filled draft you review and send.

## The whoosh

1. Press **⌘⇧Space** (configurable). A Spotlight-style panel appears, already
   pointed in a direction based on the app you were just in.
2. **Type** to filter your recent chats, **↑/↓** to move, **⇥** to swap
   direction, **Return** to send.
3. Whoosh reads the chosen conversation, assembles a handoff, and opens the
   destination app with a pre-filled composer. Review it and press Send.

No forms, no checklists — the chat you pick is the only thing that moves, and
nothing is sent automatically.

## What moves ("like you never left")

A raw transcript isn't enough to resume work, so each handoff carries:

- **A lean bootstrap** that opens the destination composer — it leads with the
  real goal and your most recent request, and points at the files below. It
  stays small (~1–2 KB) no matter how large the conversation is.
- **`BRIEF.md`** — a synthesized state-of-the-work (original goal, latest
  request, the assistant's last response, recent exchange), so the new agent
  resumes from intent instead of re-reading everything.
- **`context/`** — your project's convention files (`CLAUDE.md`, `AGENTS.md`,
  `GEMINI.md`, `.cursorrules`, …), copied so the house rules survive the tool
  switch even when the destination tool wouldn't load them natively.
- **The full transcript** (`transcript/original.*`) for depth, with byte count
  and SHA-256.

The large content rides as **local files the destination reads**, not in the
length-limited deep-link URL — so transcript size never gates how much context
moves.

## Sources and destinations

| Direction | Source read | Destination opened |
| --- | --- | --- |
| Claude Code → Codex | local Claude Code sessions via the official Claude Agent SDK (read-only) | `codex://threads/new` |
| Codex → Claude Code | Codex `app-server` via the signed Codex CLI (read-only) | `claude://code/new` |

Whoosh finds the Codex CLI wherever it is — including the copy **bundled inside
the Codex/ChatGPT desktop app** — so the Codex source works with no separate CLI
install. Both apps must be installed on the Mac for there to be anything to read
from or open into.

## Install (Apple Silicon)

Grab `Whoosh.dmg` (built by `scripts/package-dmg.sh`; self-contained — it bundles
its own Node runtime and the read-only SDK, with no dependency on your toolchain).

1. Open the DMG, drag **Whoosh** onto **Applications**.
2. Launch it. Because it is ad-hoc signed (no Apple Developer ID), macOS will say
   it can't verify the developer.
3.  → **System Settings → Privacy & Security** → **"Open Anyway"** (one time).
4. Whoosh lives in the menu bar. Press **⌘⇧Space** to open it.

## Build from source

Requirements: macOS 13+ and the Xcode Command Line Tools (Swift 5.9+).

```sh
swift build            # or: bash scripts/build-app.sh  → dist/Whoosh.app
bash scripts/build-app-direct.sh   # swiftc build that bypasses SwiftPM (see below)
bash scripts/package-dmg.sh        # self-contained dist/Whoosh.dmg (Apple Silicon)
open dist/Whoosh.app
```

To enable the **Claude Code source** locally, install its SDK once, then build:

```sh
( cd Resources/ClaudeAdapter && npm install )
bash scripts/build-app-direct.sh
```

The build then writes `Resources/ClaudeAdapter/runtime.json` pointing at your
Node; `package-dmg.sh` additionally bundles a portable Node so the packaged app
needs none. `node_modules` and `runtime.json` are per-machine and git-ignored.

> **Note on `build-app-direct.sh`:** some Command Line Tools installs ship a
> `libPackageDescription.dylib` that doesn't match their own
> `PackageDescription.swiftinterface`, which makes `swift build` fail at the
> manifest step ("Invalid manifest / Undefined symbols: Package.__allocating_init").
> The app sources compile fine with `swiftc`, so this script builds the two
> targets directly and assembles the same `dist/Whoosh.app`.

## Capability boundaries

| Capability | Status |
| --- | --- |
| Carry a synthesized brief + project conventions + full transcript | Implemented |
| Read a Codex source thread (CLI or the app's bundled CLI) | Implemented, read-only, signature-verified |
| Read local Claude Code sessions (official SDK) | Implemented, read-only; Chat/Cowork not covered |
| Open the destination with a pre-filled composer | Implemented (prefill only) |
| Automatically submit a prompt | Deliberately never supported |
| Automatically identify the foreground app's selected thread | Not supported — you pick |
| Capture the live working tree / `git diff` | Not yet — branch/commit metadata only (see Safety) |
| Transfer permissions, runtime, quota, model state, or hidden reasoning | Not supported |
| Prove the destination read the archive | Not supported — opening is not reading |

## Privacy & safety model

1. Source access starts with an explicit Connect (Codex) or an SDK read
   (Claude Code). Whoosh does not scrape app databases, read credentials, or
   touch the clipboard in the background.
2. The transcript stays local. It is not embedded into a URL; the bootstrap
   names the local files and tells the destination to treat archived content as
   untrusted historical data, not new authorization.
3. Handoff folders are created `0700`, files `0600`, under app-controlled
   Application Support; symlink redirection is rejected.
4. Git is restricted to **metadata reads** (branch, commit, repo root). Worktree
   status and diffs are intentionally not captured, because repository clean
   filters can execute scripts on even `git status` — safe live-diff capture is a
   planned, separate step.
5. The Codex CLI is signature-verified (OpenAI Developer ID) before it is run,
   and its requests are bounded. Whoosh never submits a turn.
6. The destination opens a visible, reviewable draft. Once you press Send there,
   that app's own data-handling applies.

## Handoff package format

Each handoff gets a unique directory under
`~/Library/Application Support/Whoosh/Handoffs/` and never overwrites an earlier
one:

```text
Whoosh-<timestamp>-<random>/
  BRIEF.md                   # Synthesized state-of-the-work (resume from here)
  context/                   # Copied project conventions (CLAUDE.md, AGENTS.md, …)
  transcript/original.<ext>  # Full transcript bytes, no normalization
  manifest.json              # Origin, byte/hash evidence, checkpoint, Git metadata
  CHECKPOINT.md              # Human-readable state and explicit omissions
  bootstrap.txt              # The exact reviewed bootstrap, never silently truncated
  README.txt                 # Local package handling and privacy notes
```

The deep-link bootstrap is capped at 12,000 UTF-16 units (below Claude's ~14,000
truncation point); it is a pointer, not the payload. Captured transcripts are
bounded (256 MiB archive ceiling / 240 MiB capture budget).

## Architecture

- `RelayCore` — portable Foundation models, raw archives, SHA-256, prompt
  encoding, metadata-only Git capture, the resume-digest and handoff writer.
- `RelayCore/Providers` — the read-only Codex JSON-RPC source adapter and its
  bounded stdio transport.
- `RelayApp` — the macOS SwiftUI/AppKit UI, menu-bar lifecycle, Carbon hotkey,
  the Whoosh mark and animation, source selection, and native app detection.
- `Resources/ClaudeAdapter` — the read-only Claude Code session reader
  (`adapter.mjs`) run on the bundled/local Node with the official SDK.
- `Tests/RelayCoreTests` — Swift tests with synthetic data.
- `scripts` — direct `swiftc` build, DMG packaging, icon rendering, and portable
  Python contract checks.

## Protocol references

- [Claude Desktop deep links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link): `claude://code/new`, URL-encoded `q` and `folder`, prefill only.
- [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server) and [Codex commands/links](https://learn.chatgpt.com/docs/reference/commands): capability-gated source adapter and the `codex://threads/new` draft route.

No third-party credentials, exports, conversations, or generated handoff packages
belong in this repository. All fixtures here are synthetic.
