# Mac validation result (historical)

> **Superseded.** This file recorded the Mac validation of an earlier
> pre-redesign prototype (then named *Blink*, with a form-style picker/compose
> window). The product has since been:
>
> - redesigned into the Spotlight-style **whoosh** flow (hotkey → type → Return),
> - rebranded to **Whoosh** with a new comet logo and a richer flight animation,
> - extended to carry **resume context** (a synthesized `BRIEF.md` + copied
>   project convention files + a lean, pointer-style bootstrap),
> - taught to find the Codex CLI **bundled inside the Codex/ChatGPT app**, and
> - packaged as a **self-contained `Whoosh.dmg`** (bundled Node + read-only SDK).
>
> For current behavior see [`../README.md`](../README.md); for the local
> verification checklist see [`MAC_VALIDATION.md`](MAC_VALIDATION.md). The earlier
> validation detail remains in this repository's git history.

## Still true from that validation

- The native arm64 app builds and ad-hoc signature verification passes.
- The global hotkey registers via Carbon (no Accessibility / event tap).
- The Codex connection verifies the installed CLI signature before running it.
- Handoffs preserve exact transcript bytes with byte-count and SHA-256 checks.
- Whoosh never submits a turn; opening a destination is not proof it read the files.
