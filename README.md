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

## Start fresh or switch tools

Press **⌘⇧Space**, pick a Claude Code or Codex chat, and carry its context into a
new session. Stay with the same agent or press **Tab** to switch.

## Install

**macOS 13+ · Apple Silicon download**

```sh
brew install --cask srics96/tap/whoosh
```

Or download [**Whoosh.dmg**](https://github.com/srics96/Whoosh/releases/latest/download/Whoosh.dmg),
drag it to Applications, and open it.

> **First launch, for either install:** Whoosh is ad-hoc signed, **not Apple
> Developer ID–signed or notarized**. macOS may block it. If you trust the official
> download, try opening it, then use **System Settings → Privacy & Security →
> Open Anyway** for Whoosh, if offered. Follow [Apple’s instructions](https://support.apple.com/en-ie/102445)
> and review the confirmation. This exception is not malware verification;
> keep Gatekeeper enabled.

## Use it

1. Press **⌘⇧Space** and connect your source once.
2. Choose **From**, search for a chat, and pick it with **↑ ↓**.
3. Choose **To**—a fresh session of the same agent or the other tool—and press **Return**.

**Desktop:** review the new draft in Codex or Claude desktop Code, then send.

**Terminal (manual):** use **Copy launch command** to start the destination CLI in
your project. Then **Copy bootstrap**, paste into the empty session, review and send.
Use an installed, signed-in CLI for this mode.

Whoosh prepares the context; **you decide when to send**. **Escape** cancels a
handoff. Reopen the picker to refresh chats, or use **Options → Refresh conversations**.
If a project has moved, choose its folder to continue.

## Your context, ready to continue

The local handoff brings together a brief, the captured conversation, available
project instructions and a Git snapshot. Read Claude desktop Code histories without
setting up Claude CLI; Codex reading uses its signed CLI, including the copy bundled
with the Codex app.

[How handoffs work](docs/handoffs.md) · [Build and validation](docs/development.md)

## License

Original Whoosh code and documentation: [MIT](LICENSE).
The Claude Agent SDK, bundled Node.js and other dependencies retain their own
licenses. See [third-party notices](THIRD_PARTY_NOTICES.md).
