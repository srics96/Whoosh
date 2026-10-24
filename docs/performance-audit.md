# Responsive handoff processing

The 2026-10-24 local audit compared optimized builds against `743668c` using
synthetic data. No private histories or submitted model prompts were used.

| Operation | Before | After (representative run) |
|---|---:|---:|
| Screening 1 MiB of ASCII text | 0.834 s | 0.225 s |
| Screening 16 MiB | 12.984 s | 3.355 s |
| SHA-256 import, 64 MiB | 0.302 s | 0.291 s |
| Archive write/read-back verification, 64 MiB | 0.413 s | 0.495 s |

The isolated 16 MiB scanner used 3.26 CPU seconds after the change versus 12.87
before; peak RSS was 34.9 MiB versus 35.2 MiB. During a separate 16 MiB scan,
a 10 ms main-actor heartbeat ran 297 times while the worker ran for 3.41 seconds.

These are individual wall-clock measurements on a loaded Mac, not p95 latency or
an end-to-end handoff benchmark. The improvement is in screening (about 3.9×),
not archive I/O. Screening still scales with full history size. More importantly,
screening, hashing and digest construction now run off the main actor and can be
cancelled. The original sample was entirely in Swift Regex matching/case folding.
The replacement precompiles ICU expressions, retains the original patterns and
whole-input checks, and enumerates matches with cancellation progress callbacks.
It does not cap or truncate the screened text. Errors and cancellation fail closed.

The privacy result now also gates preparation; a flagged history cannot auto-fly.
Cancellation propagates to detached workers, Codex probes, and Claude/Git helpers
owned by this operation. Cleanup waits for the owned child, escalating to SIGKILL
only if that child does not exit after SIGTERM. Existing user sessions are never
looked up or terminated. CPU cancellation checkpoints are also present in hashing
and archive preparation. Synchronous file operations can finish their current
system call before cancellation is observed.

The picker exposes **From** and **To** separately, with accessible selection values.
Tab switches the destination. Changing source keeps the safe same-agent default.
The new draft is never submitted by Whoosh.

## Reproducing checks

Normally run `swift test` and `swift build -c release`.
On the audited host, SwiftPM failed before compiling the package with a missing
`PackageDescription.Package.__allocating_init` symbol. XCTest could not run there.
No toolchain installation or system changes were made. The repository's existing
direct-compiler approach was used instead:

```sh
# Optional SDK bridge validation uses an already-installed SDK, never downloads one.
WHOOSH_TEST_NODE=/path/to/existing/node \
WHOOSH_TEST_SDK=/path/to/existing/sdk.mjs \
  scripts/check-performance-direct.sh
```

This builds the optimized core and GUI executable, runs standalone screening,
cancellation, model and pagination checks, checks the SDK adapter if provided,
and runs the portable source contracts. The model harness injects synthetic
providers and a temporary Node bridge. It never opens a destination or reads a
real history. `Tests/RelayCoreTests/PerformanceSafetyTests.swift` adds the matching
XCTest regressions for a functioning SwiftPM/XCTest host. Both old smoke tests had
stale 32 MiB / 10,000-message expectations; their fixtures now verify the existing
240 MiB / 200,000-message limits without changing product limits.

A separate UI fixture bundle with an isolated identifier and synthetic row was
used to verify the From/To labels, both Tab directions, source-reset behavior,
and Escape/hotkey reopening. The installed application was not overwritten.
Exact cold/warm panel latency, complete real-history handoffs and live cancellation
of a user's history remain unmeasured. Existing SwiftUI/AppKit deprecation and
Swift 6 isolation warnings remain outside this patch.
