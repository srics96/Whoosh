# Whoosh

**Switch agents. Keep your flow.**

Whoosh is a native macOS menu-bar app that moves a coding conversation between
**Claude Code** and **Codex** in one keystroke.

Repository: [github.com/srics96/blink](https://github.com/srics96/blink)

## The problem

If you use more than one AI coding agent, you know the tax of switching. You're
deep in a Claude Code session, you hit a wall, you want a second opinion from
Codex — and now you're copy-pasting the transcript, re-explaining what you'd
decided, what you already tried, and where the code is. The new agent always
feels like it just walked into the room mid-conversation. Switching tools costs
you your flow, so you don't switch, even when the other tool would do better.

## The solution

Press **⌘⇧Space**, pick the chat, hit **Return**. The other app opens with your
context already in the composer — not just the transcript, but a **synthesized
brief** (the goal, your most recent request, where things stand) plus your
project's **conventions** (`CLAUDE.md` / `AGENTS.md`) — so it resumes like you
never left.

- It **never submits for you** — it opens a draft you review and send.
- **Only the chat you pick** moves. Everything stays local.
- It **reads, it doesn't scrape** — a signature-verified Codex CLI and
  Anthropic's read-only SDK.

> Whoosh is an open-source prototype, not a notarized App Store release. The
> install takes one extra approval click the first time (steps below).

---

## Requirements

- **Apple Silicon Mac** (M1/M2/M3/M4), macOS 13 or later.
- **Claude Code and/or Codex installed.** Whoosh moves chats *between* them — it
  can't replace them. You also need your own chats in whichever one you use as
  the source.

## Install (about 2 minutes)

**1. Download** → **[Whoosh.dmg](https://github.com/srics96/blink/releases/latest/download/Whoosh.dmg)**
(from the [latest release](https://github.com/srics96/blink/releases/latest)).

**2. Install** — open the DMG and drag **Whoosh** onto the **Applications**
folder shown next to it.

**3. Approve it the first time** (one time only). Whoosh is open-source and
ad-hoc signed, not notarized by Apple, so macOS asks you to confirm before the
first launch. Do **one** of these:

- **Easiest — right-click to open:** in Applications, **right-click (or
  Control-click) Whoosh → Open**, then click **Open** in the dialog.
- **If macOS only offers "Move to Trash":** open  → **System Settings →
  Privacy & Security**, scroll down to the message about Whoosh, click
  **Open Anyway**, then launch Whoosh again and confirm.
- **Or one line in Terminal**, then just double-click Whoosh normally:
  ```bash
  xattr -dr com.apple.quarantine /Applications/Whoosh.app
  ```

You only do this once. After that, Whoosh opens like any other app.

**4. Done.** Whoosh lives in your **menu bar** as a small comet icon — it has no
Dock icon. Press **⌘⇧Space** to open it.

## Using Whoosh

1. Press **⌘⇧Space** from anywhere. The panel opens, already pointed in a
   direction based on the app you were just in. Press **⇥ (Tab)** to swap
   Claude Code ↔ Codex.
2. **Connect once** (first time per source): click **Connect** — Whoosh finds
   your Codex CLI (including the copy bundled inside the Codex app) and reads it
   read-only; Claude Code sessions are read through Anthropic's official SDK.
3. **Type** to filter your recent chats, **↑ / ↓** to move, **Return** to send
   the highlighted one.
4. The other app opens with your context pre-filled. **Review the draft and
   press Send** — Whoosh never sends for you.
5. The **menu-bar icon** lets you change the shortcut, swap direction, or quit.

Tip: if **⌘⇧Space** is already taken on your Mac, open the menu-bar icon and pick
the alternate shortcut.

## What moves ("like you never left")

A raw transcript isn't enough to resume work, so each handoff carries:

- **A lean bootstrap** that opens the destination composer — it leads with the
  real goal and your most recent request, and points at the files below. It
  stays ~1–2 KB no matter how large the conversation is.
- **`BRIEF.md`** — a synthesized state-of-the-work (goal, latest request, the
  assistant's last response, recent exchange), so the new agent resumes from
  intent instead of re-reading everything.
- **`context/`** — your project's convention files, copied so the house rules
  survive the tool switch even when the destination tool wouldn't load them.
- **The full transcript** (`transcript/original.*`) for depth, byte count and
  SHA-256 verified on write.

The large content rides as **local files the destination reads**, not in the
length-limited deep-link URL — so transcript size never gates how much moves.

## Capability boundaries

| Capability | Status |
| --- | --- |
| Carry a synthesized brief + conventions + full transcript | Implemented |
| Read a Codex source (CLI or the app's bundled CLI) | Implemented, read-only, signature-verified |
| Read local Claude Code sessions (official SDK) | Implemented, read-only; Chat/Cowork not covered |
| Open the destination with a pre-filled composer | Implemented (prefill only) |
| Automatically submit a prompt | Deliberately never supported |
| Automatically identify the foreground app's selected thread | Not supported — you pick |
| Capture the live working tree / `git diff` | Not yet — branch/commit metadata only |
| Transfer permissions, runtime, quota, model state, or reasoning | Not supported |
| Prove the destination read the archive | Not supported — opening is not reading |

## Privacy & safety

1. Source access starts with an explicit Connect (Codex) or an SDK read
   (Claude Code). Whoosh does not scrape app databases, read credentials, or
   touch the clipboard in the background.
2. The transcript stays local. It is not embedded into a URL; the bootstrap
   names the local files and tells the destination to treat archived content as
   untrusted historical data, not new authorization.
3. Handoff folders are created `0700`, files `0600`, under
   `~/Library/Application Support/Whoosh/Handoffs/`.
4. Git is read as **metadata only** (branch, commit, repo root). Diffs/worktree
   are not captured, because repository clean filters can run scripts on even
   `git status`.
5. The Codex CLI is **signature-verified** (OpenAI Developer ID) before it runs.
   Whoosh never submits a turn.

## Build from source

Requirements: macOS 13+ and the Xcode Command Line Tools (Swift 5.9+).

```sh
swift build                        # or: bash scripts/build-app.sh  → dist/Whoosh.app
bash scripts/build-app-direct.sh   # swiftc build that bypasses SwiftPM (see note)
bash scripts/package-dmg.sh        # self-contained dist/Whoosh.dmg (Apple Silicon)
open dist/Whoosh.app
```

To enable the **Claude Code source** locally, install its SDK once, then build:

```sh
( cd Resources/ClaudeAdapter && npm install )
bash scripts/build-app-direct.sh
```

The packaged DMG bundles its own portable Node, so the installed app needs none.
`node_modules` and `runtime.json` are per-machine and git-ignored.

> **Note:** some Command Line Tools installs ship a `libPackageDescription.dylib`
> that doesn't match their own `PackageDescription.swiftinterface`, which makes
> `swift build` fail at the manifest step. The app sources compile fine with
> `swiftc`, so `scripts/build-app-direct.sh` builds the targets directly.

## Handoff package format

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

## Architecture

- `RelayCore` — portable models, raw archives, SHA-256, prompt encoding,
  metadata-only Git capture, the resume-digest and handoff writer.
- `RelayCore/Providers` — the read-only Codex JSON-RPC source adapter and its
  bounded stdio transport.
- `RelayApp` — the macOS SwiftUI/AppKit UI, menu-bar lifecycle, Carbon hotkey,
  the Whoosh mark and animation, source selection, native app detection.
- `Resources/ClaudeAdapter` — the read-only Claude Code session reader.
- `scripts` — direct `swiftc` build, DMG packaging, icon rendering, Python
  contract checks.

## Protocol references

- [Claude Desktop deep links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link): `claude://code/new`, prefill only.
- [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server) and [Codex commands/links](https://learn.chatgpt.com/docs/reference/commands): the `codex://threads/new` draft route.

No third-party credentials, exports, conversations, or generated handoff packages
belong in this repository. All fixtures here are synthetic.
