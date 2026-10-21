# Mac validation gate

These checks are not marked passed by source inspection or Linux contract tests.

## Compile and package

- Confirm the selected executor is macOS and Swift 5.9+ is already available.
- Run `swift test`, `swift build`, and `bash scripts/build-app.sh`.
- Confirm `codesign --verify --deep --strict dist/Blink.app` succeeds.
- Do not install software, enable accessibility permissions, sign in, or grant persistent access merely to make a test pass.

## Synthetic end-to-end flow

- Launch the built app. Confirm a menu-bar icon, visible handoff window, and an accessible window title.
- Test both configured hotkey choices. Confirm registration failures/conflicts are visible. Quit and verify the shortcut is released.
- Open the overlay while another app is foreground. It may suggest the app; it must not say it knows the selected thread.
- Import `fixtures/synthetic-conversation.md`. Pick a synthetic project directory and an explicit temporary output directory.
- Enter a goal and next step; leave optional notes empty once, then provide them.
- Verify the source-stopped requirement and the separate data-transfer review requirement. No file chooser or app launch should run before the corresponding user action.
- Prepare a handoff and verify byte-for-byte archive equality, manifest byte count/hash, file modes, and an untouched synthetic project.
- Review the exact bootstrap and all path/privacy disclosures. The raw transcript must not be automatically submitted or put wholesale into the URL.
- Edit any input after preparation. Confirm the old launch action and approvals become invalid.
- Repeat prepare, Back/Cancel, and repeated-click flows. Every package has a distinct directory. Cancelled panels retain the existing valid selection or clearly leave it unchanged.
- Use a malformed/empty/over-limit source and a long checkpoint. Confirm useful errors and no partial package is left behind.

## Destination behavior

- If Claude is absent, confirm a clear missing-app state; no fabricated success, automatic install, or web fallback.
- If Claude is installed and a synthetic test launch is authorized, review and open the link. Confirm Claude Code opens, asks for the project folder, and prefills the exact short prompt without submitting it.
- The app must label completion as destination opened/prompt prefilled, not history imported/read/verified.
- For Codex, confirm the manual/open-app fallback is clearly labeled. Do not imply a native thread was created or its context prefilled unless independently demonstrated.
- Test a project path and output path containing spaces, plus signs, ampersands, `#`, and Unicode.
- Test reduced motion and VoiceOver labels; all important states must be visible without animation.

## Optional native Codex source

The user must explicitly choose an official installed Codex CLI and approve connecting. Do not inspect private native database files, scan session directories, read auth files, or automatically choose an arbitrary executable from PATH.

- Verify CLI version/schema probe has a bounded timeout and unsupported CLI fails closed.
- Verify safe-list capability is required before thread/list.
- Confirm the thread picker only contains responses from the selected CLI connection. Native desktop thread visibility is not guaranteed.
- Confirm selected history has exact raw API response bytes, correct selected ID, and explicit partial/pagination markers.
- Reject unknown IDs, malformed results, server-requested actions, and unsupported pagination without resuming/starting a thread.
- Disconnect during a request and repeat Connect. Confirm stale results do not replace a new selection and owned child processes exit.
- Live usage may be unavailable. No fake bar, reset time, or quota should be shown.

## Record evidence

Record command output, toolchain/macOS versions, synthetic scenario results, and screenshots of compose/review/completion. Never include private exported conversations or account information in the public repository or screenshots.
