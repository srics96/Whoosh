# Handoff details

## Local files, reviewed by you

Whoosh lists metadata, then reads only the conversation you select. Source adapters
are read-only. It writes a local package under
`~/Library/Application Support/Whoosh/Handoffs/` and prepares a short prompt pointing
to it. Submitting that prompt is your action and is subject to the destination
provider’s data handling.

The package can include:

- `BRIEF.md`: goal, latest request and recent exchange.
- `transcript/original.*`: captured source bytes, verified when written.
- `context/`: available `CLAUDE.md` and `AGENTS.md` instructions.
- `workspace/changes.diff`: tracked staged/unstaged changes, when available.
- `manifest.json`, `CHECKPOINT.md` and `bootstrap.txt`: scope, project and resume notes.

The destination should reconcile the snapshot with the current project before
changing anything. Untracked file contents are not copied. Diffs can be omitted
when too large, unavailable or affected by detected content filters; inspect the
package notices. Git capture disables external diff/textconv, but it is not a
sandbox: use trusted repositories because Git status runs before the filter check.

## Source limits

Codex is read through its signature-verified CLI/app-server. Claude Code is read
through the bundled official SDK, including desktop Code sessions exposed locally.
Claude captures the exposed active chain, not alternate branches, subagents or
attachment bytes. Missing history is marked partial; no native chat import,
reasoning, permissions, running processes or quota transfer is implied.

Native history capture has a 240 MiB budget; convention files are capped at 256 KiB
each. A destination may have smaller tool/context limits. In particular, Claude’s
Read tool can fail on oversized JSONL lines. A permitted read-only chunk/byte reader
may be needed; a partial read must not be described as the whole conversation.
The original archive is preserved rather than silently shortened.

## Desktop and Terminal

Desktop mode requests an unsent draft in the selected project. Confirm that the
correct app, project and draft appeared before sending.

Terminal mode is manual. **Copy launch command** copies a shell-quoted project
change followed by `codex` or `claude`, with no startup prompt. **Copy bootstrap**
copies the separate context prompt. Whoosh executes neither. Start an empty
interactive session, paste, review, then send. Complete the CLI’s own login and
workspace setup first; Whoosh does not transfer credentials or approvals.

Changing From resets To to a fresh session of that source. Tab switches the target.
Reopening refreshes metadata without rereading a selected conversation or discarding
a prepared handoff. Failed refresh keeps cached rows with an error. Escape cancels
Whoosh-owned work; it does not terminate unrelated agent sessions. A missing project
requires explicit folder selection, never an automatic home-directory fallback.
