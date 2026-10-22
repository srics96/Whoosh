# Release review (historical)

> **Superseded.** This was the source-level review of an earlier pre-redesign
> prototype (then named *Blink*), whose UI was a 580-point picker + compose form
> with an explicit "source stopped" confirmation and technical setup behind an
> Advanced disclosure.
>
> That flow has been replaced by the Spotlight-style **whoosh** (hotkey → type →
> Return, no compose form), rebranded to **Whoosh**, and extended with resume
> context and a self-contained DMG. See [`../README.md`](../README.md) and
> [`MAC_VALIDATION.md`](MAC_VALIDATION.md) for current behavior; the full earlier
> review remains in git history.

## Enduring design principles

- Only the chat you pick moves; nothing is submitted automatically.
- The transcript stays local; the bootstrap is a short pointer, not the payload.
- Git is read as metadata only (clean filters can execute on `git status`).
- The Codex CLI is signature-verified before it runs; the adapter is read-only.
- Opening a destination is "opened / prefilled", never "history read/verified".
