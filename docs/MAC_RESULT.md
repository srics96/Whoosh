# Mac validation result

## Verified

The native arm64 release builds with the existing Swift 6.0.3 Command Line Tools and macOS 15.2 SDK. Project-local manifest-interface and compiler-overlay workarounds are required on this host; no system toolchain was changed. Ad-hoc signature verification passes. The normal build script remains gated by unavailable XCTest; separate native release compilation is not a passing full build-script claim.

The physical global hotkey was confirmed by the user from their current surface. An all-app hardware matrix remains unverified. Four isolated Carbon checks passed for callback routing, unrelated IDs, exclusive conflicts and registration release.

The compact picker uses authentic installed provider icons, a revised original split-lid Blink mark and a reduced-motion-aware one-shot transition. Header-size readability was inspected in Blink screenshots; exact 20-pixel menu-template and 32-pixel app-icon assets were rendered and inspected. A missing bundled icon was fixed with Blink.icns and CFBundleIconFile. As an LSUIElement accessory, Blink has no normal Dock tile. Normal/reduced-motion preview controls were exercised without any destination launch. Actual menu-bar placement and frame-by-frame timing remain unverified.

Codex connection detection verifies the installed executable signature. Both Codex and local Claude Code connections reconnect after restart without a setup form. Search and Return selection were exercised. Actual project metadata fills the handoff automatically; missing metadata requires an explicit folder choice. Unknown source activity requires a stopped confirmation.

The approved official Claude Agent SDK 0.3.306 was installed locally with scripts and optional platform binaries disabled. Its already-installed dependencies are packaged as app resources; the existing Node runtime is used. Packaging fixed an external SDK-file read stall in the GUI-launched helper. No permission denial was bypassed or persistent security grant added. Local Claude Desktop Code metadata and a selected synthetic session were retrieved through documented read-only APIs. Chat and Cowork source coverage is unsupported.

The synthetic reverse handoff preserved 36 SDK messages in 59,804 bytes, with byte-count and SHA-256 verification. All active-chain API pages were captured. The archive remains explicitly partial relative to original logs: branches, subagents, external attachment bytes and non-message records are outside this export. macOS confirmed the native Codex draft request. Blink never submits a prompt.

For the forward handoff, Claude displayed the correct native composer, project folder and complete short bootstrap after an explicitly approved synthetic workspace trust. No automatic submission occurred. The test agent explicitly submitted one read-only synthetic receipt test; the provider remains at Starting session with no response or actionable error. No duplicate submission or app-wide restart occurred.

## Current checks

- 10 Claude adapter checks pass: official SDK paginated reading, source mutation, repeated items, list pagination, identity mismatch, wrong project, empty history, message cap, byte cap and equivalent Unicode paths.
- 9 portable contract checks pass.
- 8 Codex pagination/resource smoke checks pass, including 1200 items across 12 pages with newest context, deadline/byte-budget rejection, active-source rejection and cancellation under one second. Normal capture drains to exhaustion within 32 MiB/60 seconds; failures block handoff rather than offering an old prefix.
- 16 native core smoke assertions passed earlier for preservation, hashes, storage, links and sensitive-content screening.
- 24 XCTest cases remain unrun: no such module XCTest.
- Release compilation and strict ad-hoc signature verification pass.

## Release limits

Codex UI inspection was explicitly denied. Its composer display and context receipt are therefore unverified. Claude receipt/continuation remains blocked by provider startup. These native staging milestones are not end-to-end completion.

Sensitive-content scanning detects common credential/card patterns, not every kind of PII or secret. Provider confirmations remain intact. No native chat database is written, no credentials are read, and no unrelated history is transferred.

The supported Library upload failed during prepare_uploads; no saved IDs were returned. GitHub integration writes remain denied and no alternate publication route was attempted. Source archives exclude histories, personal paths, session IDs, dependencies, logs and screenshots. Clean Blink screenshots exist in the tool conversation only; no local screenshot file was produced.

See RELEASE_REVIEW.md for final source-level findings and corrections.


## Latest design revision
See RELEASE_REVIEW.md for the conversation-first redesign and its precise visual-test boundaries. The latest app uses a readable 580-point picker, selected conversation card, explicit Continue action and Close/Escape, with technical setup in Options. Exact active-session detection and destination context receipt remain unverified.
