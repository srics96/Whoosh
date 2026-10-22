# Mac validation gate

These checks need a real Mac; they are not satisfied by source inspection or the
portable contract tests. Use synthetic fixtures until you deliberately choose a
real conversation.

## Compile and package

- Confirm macOS 13+ and the Xcode Command Line Tools (Swift 5.9+) are present.
- Build: `swift build`, or `bash scripts/build-app-direct.sh` if `swift build`
  fails at the manifest step (see the README note on `libPackageDescription`).
- Confirm `codesign --verify --deep --strict dist/Whoosh.app` succeeds.
- For the distributable: `bash scripts/package-dmg.sh`, then confirm the app in
  the DMG runs with **no external Node** (the bundle carries its own).
- Do not install software, enable Accessibility, sign in, or grant persistent
  access merely to make a test pass.

## The whoosh (synthetic end-to-end)

- Launch the app. Confirm the menu-bar comet icon and that **⌘⇧Space** opens the
  Spotlight panel. Confirm a shortcut conflict is shown as an error, and the
  shortcut is released on quit.
- Open the panel from different foreground apps. The direction may be suggested
  from the foreground app; it must never claim to know the selected thread.
- Type to filter, **↑/↓** to move, **⇥** to swap, **Return** to send. Confirm the
  highlighted row is the one that flies.
- After a handoff completes, press the hotkey again: it must return to a fresh
  picker, not the previous completion screen.
- Inspect the generated folder under `~/Library/Application Support/Whoosh/Handoffs/`:
  `BRIEF.md` (goal + latest request + recent exchange), `context/` (copied
  convention files when present), `transcript/original.*` (byte-for-byte, matching
  manifest byte count + SHA-256), `0700`/`0600` modes, and an untouched project.
- Confirm `bootstrap.txt` stays small and points at the files; the full transcript
  is never put wholesale into the URL, and nothing is submitted automatically.
- Try a very long conversation; confirm it captures within the budget rather than
  failing at the old 32 MiB limit.

## Destination behavior

- If the destination app is absent, confirm a clear missing-app state — no
  fabricated success, auto-install, or web fallback.
- With the app installed and a synthetic launch authorized: confirm the composer
  opens with the prefilled bootstrap, asks for the project folder as the provider
  requires, and does **not** submit.
- Completion must read as "opened / prefilled", never "history imported/read/verified".
- Test project/output paths containing spaces, `+`, `&`, `#`, and Unicode.
- Test Reduce Motion and VoiceOver: all important states must be legible without
  the animation.

## Codex source (CLI + bundled-in-app)

- Confirm detection finds a signed Codex CLI — including the copy inside the
  Codex/ChatGPT app — and that an unsigned/mismatched binary fails closed.
- Verify the version/schema probe is bounded and an unsupported CLI fails closed.
- Confirm the picker only shows threads from the connected CLI, selected history
  has exact raw API bytes with partial/pagination markers, and unknown IDs,
  malformed results, server-requested actions, and bad pagination are rejected.
- Disconnect mid-request, then reconnect: stale results must not replace a new
  selection, and owned child processes must exit.

## Claude Code source (bundled Node + SDK)

- With `Resources/ClaudeAdapter` populated (`npm install`) and `runtime.json`
  wired, confirm the adapter lists and reads local sessions read-only, and that
  it works under a restricted `PATH` using the bundled Node.
- Confirm Chat/Cowork are not claimed, and that a changed source during read is
  rejected rather than silently captured.

## Record evidence

Record command output, toolchain/macOS versions, synthetic results, and
screenshots of the picker / whoosh / completion. Never include private exported
conversations or account information in the repository or screenshots.
