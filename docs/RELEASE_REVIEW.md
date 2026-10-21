# Release-readiness source review

Status: native staging is verified within the recorded provider boundaries; end-to-end context receipt is not verified.

## Fixed findings

1. RelayModel.selectNativeThread/selectClaude previously retained the old selection while a new read was attempted. A failed read could leave the old chat transferable. Both now clear the old conversation before starting the read. A live failed-selection case showed Continue disabled; the corrected synthetic selection subsequently passed.
2. launchCodex silently returned when the destination app was missing. It now clears transfer approval and reports that the archive remains preserved and the official app is unavailable.
3. Preparation checked source activity but did not consistently reject changed project/history metadata. It now compares Codex modification time and cwd, and Claude session identity, cwd, modification time and file size. Active Codex sources are rejected; unknown activity requires explicit stopped confirmation.
4. The Claude bridge now rejects mismatched session identity, wrong project, empty history, changing sources and repeated page items. Equivalent NFC/NFD path representations are normalized; different projects remain rejected. The initial strict-path regression was found by native synthetic selection and fixed before delivery.
5. Reader errors now expose only whitelisted categories, never arbitrary SDK error text or transcript contents.

## Other reviewed boundaries

- Duplicate actions: synchronous stage changes disable preparation/opening; launch functions require review stage. No API or UI submit action exists in Blink. Open success means only a draft request. There is no automatic retry after uncertain provider outcomes.
- Codex export: normal selection drains full thread/items/list pages across turns until exhaustion, with 100 items per page, a 32 MiB archive budget and a 60-second deadline. Deadline/byte failures return no transferable prefix. Repeated cursors are rejected. Cancel, Escape and the close control cancel a source read; in-flight cancellation was verified under one second. Explicit limited-page reads remain available only for metadata preflight/tests and are marked partial; the normal selection path rejects partial results. No summary-view substitution.
- Claude export: 100-message pages, maximum 10000 messages and 32 MiB message payload. API exhaustion is explicit. Original-log completeness is never claimed; branches/subagents/attachment bytes are outside capture.
- Long prompts: bootstrap URLs reject over-budget text instead of truncating it. Full histories stay in private local archives.
- Missing helper/runtime: connection fails visibly. SDK is packaged in the build; consent survives restart. Existing Node remains a host dependency, so this is not a portable installer.
- Private storage: unique packages, restrictive permissions, exact saved-byte/hash checks and symlink rejection remain in place.
- Branding: revised original mark is legible in the compact overlay, the exact 20-pixel menu template render and the 32-pixel app-icon render. Fixed missing bundled .icns and CFBundleIconFile; the asset is generated from the runtime drawing code. Blink is intentionally an LSUIElement accessory and has no normal Dock tile. Actual menu-bar placement and frame-by-frame animation timing remain human visual checks. Both Blink-only preview modes were exercised; reduced motion disables geometry collapse and uses opacity. A preview-only arrow overlap was fixed. Real provider icons are unchanged.

## Evidence

The reviewed release compiles and passes strict ad-hoc signature verification. Ten adapter checks and nine portable checks pass. Native restart, automatic reconnection and synthetic selection passed on the reviewed build. Eight current native Codex pagination/resource checks pass, including 12 pages/1200 items with the newest item, deadline and byte-budget rejection, active-source rejection and responsive cancellation. Earlier core checks remain applicable. XCTest is unavailable, and native smoke checks are not presented as XCTest.

The existing synthetic Claude submission remains at Starting session. Codex UI inspection remains denied. Neither boundary was bypassed or disguised as successful context receipt.

The targeted startup recovery check found no normal Stop action for the stalled disposable Claude session in the permitted text surface. Its terminal state cannot be verified, so no replacement submission was made.


## Conversation-first redesign checkpoint

The latest native build replaces the compact form with a 580-point readable picker and a selected-conversation card. Rows wrap titles, show project and compact relative activity, and explicitly say Review. Selection leads to one large Continue in Claude Code or Continue in Codex action; Return triggers it. The footer is outside scrolling content. Close is visible and has an explicit Escape shortcut. Connection/import/helper controls are secondary. Only exact locally recorded owned fixture IDs are hidden by default; no user chats are deleted or filtered by a guessed title pattern.

The selected card remains present during actual preparation. Opening moves/scales/fades the card toward the destination badge; Reduce Motion uses opacity only. The panel hides after macOS confirms the open request, without delaying the real launch for animation. A fixed opaque native background also avoids transparency dependence. Launch failures retain the selected context and report the next action. Every preparation eligibility failure now has a visible reason.

Exact active-chat identification is not supported by the inspected interfaces. Foreground application is captured before Blink activates, but only suggests the source provider. It never identifies or guesses a thread. Claude support remains local Code sessions, not Chat or Cowork.

Verification: release compile and strict ad-hoc signature verification passed. Nine portable checks passed. Blink-only synthetic screenshots verified readable picker and selected-card layouts, visible close, counterpart icon and enabled primary action. Return reached explicit preview completion in normal and reduced-motion modes; no app was opened by those previews. Preview mode suppresses automatic source connection and was turned off afterward. The latest build was left running with its panel hidden. Native visual observation reactivates the bound app, so Escape-hidden persistence and frame-by-frame motion timing are not conclusively established by that tool. The source has an explicit Escape shortcut and panel cancellation handler; user hardware confirmation remains useful. No new real history transfer or receiving-app test was performed.

An attempted SDK session enumeration for QA was automatically denied because it could list unrelated sessions before filtering. It was not retried. Fixture exclusion used only previously verified exact synthetic IDs from an existing synthetic archive. No additional access grant is pending.
