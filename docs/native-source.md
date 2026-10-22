# Codex native-source adapter

## Status

Implemented and exercised on macOS against an installed Codex CLI (connect + list + read). Whoosh detects a signature-verified CLI from the usual locations **and the copy bundled inside the Codex/ChatGPT desktop app**, so the Codex source works without a separate CLI install. No user's app, session, or authentication directories are inspected. Desktop/cloud conversation visibility beyond what the connected CLI returns is **unverified**. An empty list means only that this process returned no eligible records, not that the user has no conversations.

## Official protocol basis

The [official App Server documentation](https://learn.chatgpt.com/docs/app-server) describes stdio JSONL, the `initialize`/`initialized` handshake, version-specific generated schemas, and history retrieval without resuming. `thread/list` defaults to CLI/VS Code sources and can scan logs to repair metadata; `useStateDbOnly: true` avoids that scan. `thread/read` obtains metadata, and `thread/items/list` pages persisted items. Item pagination may be unsupported by a particular store. `account/rateLimits/read` reports quota windows when available. These APIs do not establish that a standalone CLI shares every desktop or cloud history.

The same documentation labels app-server/WebSocket support experimental. This implementation uses stdio, not a WebSocket listener, and remains a prototype pending installed-version testing.

## Integration contract

Files are isolated under `Sources/RelayCore/Providers`:

- `CodexSourceModels.swift`: public wire-independent UI models and an injectable read-only transport protocol.
- `CodexNativeSourceProvider.swift`: selected-thread discovery, bounded capture, and optional usage retrieval.
- `CodexStdioTransport.swift`: child-process transport and a fail-closed schema preflight.

Create `CodexNativeSourceProvider()`. From an explicit **Connect** action, pass the user-selected trusted executable URL and `userApproved: true` to `connect`. No shell search, automatic installation, app-container enumeration, or session-file import occurs. The CLI is responsible for its ordinary configuration and account handling; launching it is not a guarantee of zero internal side effects. Whoosh does not perform login or read credentials. The child inherits only an allowlist of ordinary environment variables, not API keys or token variables. Custom `CODEX_HOME` profiles are intentionally not inherited.

Connect runs bounded `--version` and schema-generation commands. Generated JSON is inspected only in a unique Whoosh-owned temporary directory, which is removed afterward. The schema must advertise the database-only list option together with the list parameter shape. Otherwise, connection fails before listing. There is no fallback to a scanning list request.

After connect:

1. `listThreads(cursor:limit:)` returns one picker page and `nextCursor`. Request another page only when needed. Sources are explicitly `cli`, `vscode`, and `appServer`; archived threads and subordinate-agent categories are excluded.
2. `readThread(id:maxPages:pageSize:)` accepts only an ID returned by this connection's list. It fetches metadata followed by oldest-first item pages (100 per page) until the thread is drained, bounded by a 240 MiB archive budget and a capture time budget. Unsupported pagination is a surfaced error, never a resume or deprecated full-history fallback.
3. `readRateLimits()` is a separate user-requested refresh. A missing/error result must appear as unavailable, not 0% or unlimited. This is account quota, not a selected conversation's context-window fullness or a price estimate.
4. Call `disconnect()` when finished. A timeout, cancellation, malformed/oversized response, or unexpected server request closes Whoosh's child connection. Explicit disconnect cancels any probe and awaits bounded termination of owned children, escalating TERM to KILL if needed. No background polling occurs.

The transport's method enum has no write, start, resume, fork, login, reset-credit, billing, shell, or filesystem operation. It does not attach to or interrupt an existing desktop process.

## Preservation and disclosure

`CodexSelectedThread.rawResponsesJSONL` concatenates the exact received metadata/item response lines, preserving their delimiters and response IDs. It is an **API-response capture**, not a byte-for-byte copy of the original native conversation store. Unknown response fields remain in the capture. Raw responses may contain tool results, private material, or other items absent from the readable view. Apply the handoff's review/redaction and destination-consent boundary before sharing.

`messages`/`renderedTranscript` include only user text and agent text. They deliberately exclude tool output, reasoning items, images, and unknown item types. Keep `preservationNotice` visible and record `isPartial` in the handoff manifest. A non-null next cursor means capture stopped before all items were read. Capture begins with the oldest items, so newer conversation items may be missing. Do not call any generated transcript or capture a lossless native archive. Separate requests are not an atomic snapshot; stop the source agent before creating a checkpoint and treat a running source as potentially changing.

## Mac acceptance checklist

- Build and test with the minimum supported Swift/macOS toolchain.
- Select an official installed Codex CLI; validate version/schema generation and temporary-file cleanup.
- Confirm no source process launches before Connect; verify Disconnect, application quit, probe cancellation, and timeout cleanup.
- Run the synthetic persistent-pipe transport test: a short reply must complete while stdout stays open, and a final reply must survive immediate EOF.
- Use synthetic conversations first. Confirm list source visibility without changing native history.
- Confirm exact received response bytes, chronological readable text, pagination, and partial-history labeling.
- Exercise older/unsupported CLI, unsupported item store, malformed reply, timeout, and missing quota cases.
- Confirm no credentials, transcript bytes, or stderr are written to logs.
- Verify any actual desktop conversation selected by the user, rather than claiming desktop parity from protocol support alone.
