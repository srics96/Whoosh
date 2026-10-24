# ☄️ Whoosh

**Switch agents. Keep your flow.**

Jump a coding chat between **Claude Code** and **Codex** in one keystroke — with
your context already loaded, like you never left.

## Why

Switching AI agents means copy-pasting transcripts and re-explaining everything
you'd already decided. The new agent always walks in mid-conversation — so you
don't switch, even when the other one would crush it.

Whoosh fixes that. **⌘⇧Space → pick the chat → Return.** A fresh session opens with
the goal, your last request, your project's conventions, and your **uncommitted diff**
already in the composer. You review, you send. Whoosh. 💨

Two moves, one hotkey:

- **Same agent, fresh session** — your chat has gotten long and the model's drifting?
  Whoosh it into a clean session of the *same* tool with the full context reloaded. No rot.
- **Switch tools** — hit **Tab** and send it to the other agent (Claude Code ⇄ Codex) instead.

## Install

**Homebrew:**

```sh
brew install --cask srics96/tap/whoosh
xattr -dr com.apple.quarantine "/Applications/Whoosh.app"   # approve it once
```

(Whoosh is ad-hoc signed, not notarized, so macOS quarantines it. Homebrew removed
`--no-quarantine` in 5.0, so you clear the flag yourself — or just right-click → Open.)

**Or download** → [**Whoosh.dmg**](https://github.com/srics96/Whoosh/releases/latest/download/Whoosh.dmg) → drag to Applications → **right-click → Open → Open** the first time.

Then hit **⌘⇧Space**. Whoosh lives in your menu bar (the comet). ☄️

> Needs an **Apple Silicon Mac** + **Claude Code and/or Codex** installed.
> Whoosh moves chats between them; it doesn't replace them.

## Use it

| Key | Does |
| --- | --- |
| **⌘⇧Space** | open Whoosh |
| type / **↑ ↓** | filter and pick a chat |
| **Return** | whoosh it into a fresh session of the same agent |
| **Tab** | flip to sending it to the other agent instead |

First time, click **Connect** once per source. The other app opens pre-filled —
review it and press Send. **Whoosh never sends for you.**

## What actually moves

Not just the transcript — a short **brief** (the goal + where you are), your
**`CLAUDE.md` / `AGENTS.md`** conventions, your **uncommitted diff** and changed-file
list, and the full history, dropped as local files the new agent reads. The diff is
what makes this un-copy-pasteable: the new session resumes on the actual state of your
tree, not a stale snapshot. Nothing bulky gets crammed into a URL, so big chats move fine.

## Good to know

- Reads **only the chat you pick** — read-only, all local, nothing auto-sent.
- Codex via its signed CLI (even the one inside the Codex app); Claude Code via
  Anthropic's official SDK.
- Open-source prototype, **ad-hoc signed, not Apple-notarized** — that's why it
  needs one Gatekeeper approval (right-click → Open, or the `xattr` line above).

<details>
<summary><b>Build it yourself</b></summary>

macOS 13+ and the Xcode Command Line Tools (Swift 5.9+).

```sh
bash scripts/build-app-direct.sh   # → dist/Whoosh.app  (swiftc build; see note)
bash scripts/package-dmg.sh        # → dist/Whoosh.dmg  (self-contained, Apple Silicon)
open dist/Whoosh.app
```

For the **Claude Code source**, install its SDK once first:

```sh
( cd Resources/ClaudeAdapter && npm install )
```

Note: some Command Line Tools installs make `swift build` fail at the manifest
step (a `libPackageDescription` mismatch). `build-app-direct.sh` compiles the
targets with `swiftc` directly to dodge that.

</details>

<details>
<summary><b>How the handoff works + what's in the package</b></summary>

Whoosh reads your chat, writes a resume packet to
`~/Library/Application Support/Whoosh/Handoffs/`, then opens the other app with a
short bootstrap that points at it:

```text
Whoosh-<timestamp>-<random>/
  BRIEF.md                   # Goal, latest request, recent exchange — resume from here
  context/                   # Copied CLAUDE.md / AGENTS.md conventions
  workspace/changes.diff     # Your uncommitted staged + unstaged diff
  transcript/original.<ext>  # Full transcript (SHA-256 verified on write)
  manifest.json              # Byte/hash evidence, checkpoint, Git metadata
  CHECKPOINT.md  bootstrap.txt  README.txt
```

Git is read **read-only** — branch/commit, the changed-file list, and the
uncommitted diff — with system/global config disabled and external diff/textconv
off, so no repository-defined program runs. If the repo declares content filters
(clean/smudge), the diff content is skipped and only the file list is included.
The Codex CLI is signature-verified before it runs. Opening a destination means it
opened pre-filled, not that the agent read it.

**Code:** `RelayCore` (models, archives, handoff writer), `RelayCore/Providers`
(read-only Codex adapter), `RelayApp` (SwiftUI/AppKit UI, hotkey, animation),
`Resources/ClaudeAdapter` (Claude session reader), `scripts` (build/package/icons).

**Protocols:** [Claude deep links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link) · [Codex app-server](https://learn.chatgpt.com/docs/app-server)

</details>

---

Open-source. No credentials, exports, or real conversations live in this repo —
fixtures are synthetic.
