<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/whoosh-logo-dark.png">
    <img src="docs/whoosh-logo-light.png" alt="Whoosh" width="300">
  </picture>
</p>

<p align="center"><b>Switch coding agents or start a fresh session with a local context handoff.</b></p>

<p align="center">
  <img src="docs/whoosh-demo.gif" alt="Whoosh: pick a chat, press Return, and open a fresh draft with a local context handoff" width="760">
</p>

---

## What it does

One hotkey, **⌘⇧Space**, prepares a handoff from a **Claude Code** or **Codex**
coding session. Pick a chat and press Return to open a new draft with a short prompt
pointing to local context files: your goal, latest request, available project
conventions, captured transcript, and tracked uncommitted diff when available.
You review the draft and press Send; the prompt asks the destination agent to read
those files.

Two moves, one hotkey:

- **Fresh session** — your chat has gotten long and the model is drifting? Whoosh it
  into a clean session of the *same* agent with a context handoff to read.
- **Switch tools** — press **Tab** and send it to the other agent instead.

## Install

```sh
brew install --cask srics96/tap/whoosh
```

Or download [**Whoosh.dmg**](https://github.com/srics96/Whoosh/releases/latest/download/Whoosh.dmg),
drag it to Applications, then open Whoosh.

Then press **⌘⇧Space**. Whoosh lives in your menu bar under its monochrome comet mark
(the app and wordmark use the teal-to-blue version shown above).

> **First launch:** The downloadable app is **ad-hoc signed, not Apple-notarized**.
> If macOS blocks it, review the warning and only continue if you trust the download.
> After attempting to open it, use **System Settings → Privacy & Security → Open Anyway**
> for Whoosh, as described in [Apple's guidance](https://support.apple.com/en-us/102445).
> Source availability is not a substitute for signing, notarization, or a security review.

> Needs **macOS 13+**. The downloadable DMG targets **Apple Silicon**. Reading Codex
> sessions requires its signed CLI (including the copy bundled with the Codex app).
> Opening a draft requires the **Codex desktop app** or **Claude desktop app with Code**.
> Claude sources are local Claude Code sessions exposed by its SDK, not general
> Claude Chat/Cowork history. Whoosh does not replace either agent or its account.

## How to use it

| Key | Does |
| --- | --- |
| **⌘⇧Space** | open Whoosh |
| type / **↑ ↓** | filter and pick a chat |
| **Return** | prepare the selected chat's handoff and request a new draft |
| **Tab** | switch target — fresh session ⇄ the other agent |

First time, click **Connect** once per source agent. Whoosh requests a pre-filled
destination draft; check it, review the context, and press Send yourself.
**Whoosh never submits the prompt for you.** Opening the app does not verify that
it displayed the draft or read the context files.

## What actually moves

Not just the transcript. Whoosh carries:

- a short **brief** — the goal and where you are,
- your **`CLAUDE.md` / `AGENTS.md`** conventions,
- your **tracked uncommitted diff** and changed-file list when capture succeeds,
- the transcript content returned by the selected source adapter.

These are local files, not a transcript embedded in a URL. The new agent is asked to
reconcile the snapshot with the current working tree before making changes.
Untracked file contents are not copied; large or unavailable diffs can be omitted.

This is a context handoff, **not a native chat import or a guarantee of complete
context**. Provider APIs may return partial history; Claude captures its exposed
active conversation chain, not alternate branches or subagents. Attachment bytes,
hidden reasoning, permissions, running tools, and usage quotas do not transfer.
Native history capture has a 240 MiB budget, and convention files are capped at
256 KiB each. Review the packet before sharing it with another agent.

## Good to know

- Lists session metadata for the picker, then reads the chat you select. Source
  adapters are read-only; the handoff is written locally and no prompt is auto-submitted.
  Submitting the draft to an agent is subject to that provider's data handling.
- Codex via its signed CLI (even the one inside the Codex app); Claude Code via
  Anthropic's official SDK.
- Git capture does not intentionally change your project. External diff/textconv
  are disabled, and detected content filters cause diff content to be skipped.
  This is not a sandbox: Git status is collected before that filter check, so use
  trusted repositories rather than assuming no repository-configured program can run.
- Handoff files can contain sensitive conversation or source-code content. Keep the
  output folder private and review what the destination will be allowed to read.
- The downloadable app is **ad-hoc signed, not Apple-notarized**; see the first-launch
  note above.

<details>
<summary><b>Build it yourself</b></summary>

macOS 13+ and the Xcode Command Line Tools (Swift 5.9+).

```sh
bash scripts/build-app-direct.sh   # → dist/Whoosh.app  (swiftc build; see note)
open dist/Whoosh.app
```

For the **Claude Code source** in a local build, install Node.js/npm and the SDK
**before building**:

```sh
( cd Resources/ClaudeAdapter && npm ci )
bash scripts/build-app-direct.sh
```

To build the self-contained Apple Silicon DMG (bundles Node and the SDK):

```sh
bash scripts/package-dmg.sh        # → dist/Whoosh.dmg
```

Note: some Command Line Tools installs make `swift build` fail at the manifest step (a
`libPackageDescription` mismatch). `build-app-direct.sh` compiles the targets with
`swiftc` directly to dodge that.

</details>

<details>
<summary><b>How the handoff works + what's in the package</b></summary>

Whoosh reads your chat, writes a resume packet to
`~/Library/Application Support/Whoosh/Handoffs/`, then opens the destination with a short
bootstrap that points at it:

```text
Whoosh-<timestamp>-<random>/
  BRIEF.md                   # Goal, latest request, recent exchange — resume from here
  context/                   # Copied CLAUDE.md / AGENTS.md conventions
  workspace/changes.diff     # Tracked staged + unstaged diff, when available
  transcript/original.<ext>  # Captured source content (SHA-256 verified on write)
  manifest.json              # Byte/hash evidence, checkpoint, Git metadata
  CHECKPOINT.md  bootstrap.txt  README.txt
```

The Codex CLI is signature-verified before it runs. Opening a destination means it opened
pre-filled, not that the agent read it.

**Code:** `RelayCore` (models, archives, handoff writer), `RelayCore/Providers` (read-only
Codex adapter), `RelayApp` (SwiftUI/AppKit UI, hotkey, animation), `Resources/ClaudeAdapter`
(Claude session reader), `scripts` (build/package/icons).

**Protocols:** [Claude deep links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link) · [Codex app-server](https://learn.chatgpt.com/docs/app-server)

</details>

---

## License

Original Whoosh code and documentation are available under the [MIT License](LICENSE).
Third-party components retain their own licenses and terms, including Anthropic's
Claude Agent SDK and the bundled Node.js runtime. See [third-party notices](THIRD_PARTY_NOTICES.md),
including the outstanding Node license packaging gap. The bundled app is not
entirely MIT-licensed.

The included conversation fixture is synthetic.
