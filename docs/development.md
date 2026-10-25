# Development and validation

End users do not need Xcode. These tools are for building or testing Whoosh itself.

## Build locally

Use macOS 13+ and a compatible Swift toolchain (Swift 5.9+). For Claude source support,
install the adapter dependencies with an existing Node.js/npm installation:

```sh
(cd Resources/ClaudeAdapter && npm ci)
bash scripts/build-app-direct.sh
open dist/Whoosh.app
```

The direct build uses `swiftc`, assembles the app and ad-hoc signs it. It does not
install, upload or notarize the app. This also avoids SwiftPM manifest failures on
some mismatched Command Line Tools installations.

```sh
bash scripts/package-dmg.sh
```

Packaging bundles Node and the SDK. Preserve and verify their version-matched
licenses as described in [third-party notices](../THIRD_PARTY_NOTICES.md).

## Checks

With a working XCTest toolchain:

```sh
bash scripts/check.sh
```

The standalone checks are also available without XCTest:

```sh
WHOOSH_TEST_NODE="$(command -v node)" \
WHOOSH_TEST_SDK="$PWD/Resources/ClaudeAdapter/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs" \
bash scripts/check-performance-direct.sh
```

These cover screening, pagination, bounded processes, timeout/cancellation,
project validation, terminal preparation, metadata refresh and stale-result
rejection. They are not a substitute for the full XCTest suite.

## Local acceptance — 2026-10-25

The 0.2.2 hardening changes passed optimized direct builds and focused
model, scanner, pagination, process, SDK and portable-contract checks. Actual
production Copy buttons were clicked in a synthetic development UI: both target
launch commands and separate bootstraps pasted correctly without execution.

Disposable real chats verified source discovery for Claude desktop Code, Claude CLI
and Codex CLI; fresh-session context recovery in Claude desktop, Codex CLI and
Claude CLI’s supported noninteractive interface; new-chat refresh; and larger
conversation recovery. A user manually verified one Whoosh-opened Codex desktop
session. Test prompts were narrowed for verification rather than submitting the
default bootstrap unchanged. No private histories were used.

Remaining verification limits:

- Claude CLI noninteractive success does not prove interactive Terminal onboarding.
- Codex desktop automation was unavailable; desktop-only source creation and all
  desktop routes were not exhaustively exercised.
- Large JSONL lines exceeded Claude Read’s limit in one test. A specifically allowed
  read-only tail command recovered the requested final context; that does not prove
  every byte was read by the destination.
- One earlier Git timeout was not reproduced. Process completion/cancellation and
  diagnostics were hardened, but its original root cause remains unproven.
- Full XCTest was **not run**: the installed Command Line Tools lacked XCTest, after
  a manifest-interface mismatch was isolated. The user chose to skip installing
  full Xcode. No system developer settings were changed.

These are bounded acceptance results, not a guarantee of complete context transfer
or universal agent compatibility. The installed stable app was not replaced during
this validation, before release packaging.
