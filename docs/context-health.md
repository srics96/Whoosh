# Context health nudges

Open Whoosh and choose **Options → Heavy-chat nudges**. Nudges are off by
default and require macOS notification permission and a connected source.
Whoosh offers to start at login once. Declining still allows nudges while
Whoosh is running. Login registration can be managed in macOS Login Items.

Whoosh checks recently modified local sessions once a minute. Chat size is
estimated from file size at four bytes per token, including JSONL overhead.
The first nudge threshold is 60% of a fixed baseline (200k for Claude Code,
272k for Codex); the second is 85%. The estimate is not the model's live
context, a bill, or an exact token count. Files must be unchanged for at least
60 seconds, and a five-minute collection window lets nearby crossings share
one notification. A chat that resumes during that window drops out until
it is idle again. Only chats modified in the past 30 minutes are considered.

- Whoosh checks Codex quota through the approved helper only when a Codex
  notification is due. A known active Codex window at 90% or more takes
  priority and recommends Claude. Whoosh does not check Claude quota.
- Otherwise, Whoosh can recognize a dominant multiline paste, file read, or
  tool output from a complete record in the first 1 MiB of an eligible log.
  A group samples at most four chats. Unrecognized, later, or larger records
  receive the generic advice. Notification content includes advice, and for
  a group, short project labels; it excludes chat titles and message text.
- Clicking a notification body highlights the chat and sets its destination.
  Press Return to prepare and review the handoff. **Hand off now** on a
  single nudge skips the picker and requests an unsent desktop draft or
  opens the terminal preparation screen. Either action on a grouped nudge
  lists the flagged chats so you can pick one. Whoosh never sends the prompt.
- **Not now** suppresses further nudges at that threshold. Five snoozes in
  a row trigger one tip and double the wait between subsequent notifications
  until you act on a nudge. Turning nudges off stops polling and removes
  Whoosh's nudge notifications.
- Review the brief in Whoosh or from the handoff files. It surfaces recent
  context and selected earlier decision excerpts. A skipped paste or output
  stays in the preserved archive to the extent the source exposes it.
  Savings compare the estimated original size with the bootstrap and brief;
  they do not include later archive reads. Options shows the running estimate
  across successful handoff preparations, including manual ones.

The watcher only examines standard local Claude Code project logs and local
Codex rollouts exposed by the approved Codex helper. Claude Chat, Cowork,
cloud-only conversations and nonstandard storage are outside v1. Full
history capture still requires a chat selection or the **Hand off now**
action. Whoosh stores threshold state and savings locally. It does not log
chat content, read credentials, or modify the source.

## Validation

Run the standalone checks with the installed Claude SDK:

```sh
WHOOSH_TEST_SDK="$PWD/Resources/ClaudeAdapter/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs" \
  bash scripts/check-performance-direct.sh
```

The synthetic fixtures exercise threshold boundaries, mid-flow and resumed
chats, single and grouped delivery eligibility, quota priority, a 3,000-line
paste, large file and tool output, an earlier decision, snooze backoff, the
notification body and direct handoff routes, archive integrity, and savings
persistence. They do not ask macOS for permission or launch an agent.

For native acceptance, use a test account and disposable chats. Check that
denying notification permission leaves nudges off, that one idle heavy chat
produces a banner with both actions, and that two heavy chats in separate
projects produce one banner with both flagged in Whoosh. Confirm that
**Hand off now** opens an unsent draft, **Not now** suppresses repeats, and
quitting stops new nudges. Test login opt-in and decline separately. Avoid
submitting the bootstrap to test draft creation.
