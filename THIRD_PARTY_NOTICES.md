# Third-party components and notices

The [MIT license](LICENSE) covers original Whoosh code and documentation.
It does not replace third-party licenses, grant rights to third-party trademarks,
or relicense the applications and services Whoosh works with.

## Claude Agent SDK

The Claude adapter depends on `@anthropic-ai/claude-agent-sdk` version `0.3.306`,
recorded in [package-lock.json](Resources/ClaudeAdapter/package-lock.json).
This SDK is not covered by Whoosh's MIT license. Its published package includes
Anthropic's copyright and a `LICENSE.md` referring to its
[legal agreements](https://code.claude.com/docs/en/legal-and-compliance).
See also the SDK's [license and terms](https://github.com/anthropics/claude-agent-sdk-typescript#license-and-terms).
Retain the SDK's supplied license and notices; its use and redistribution remain
subject to its own applicable terms.

The DMG packaging script copies the adapter's installed dependencies and removes
the platform-specific native Claude CLI packages. It still includes the main SDK.
Removing those binaries does not change the SDK's license.

## Node.js

The DMG packaging script bundles Node.js `v22.23.4`. Node.js and its included
components have their own copyright notices and licenses. Preserve the complete,
version-matched [Node.js LICENSE](https://github.com/nodejs/node/blob/v22.23.4/LICENSE)
alongside the redistributed runtime, including its third-party notices.

**Packaging gap:** the current script copies the Node executable but does not copy
that LICENSE file. This document does not fix the package contents or certify
existing downloads. A packaging update and verification of the resulting app/DMG
are still needed before treating that notice requirement as resolved.

## Transitive npm dependencies

Installed dependencies retain their respective licenses. The committed lockfile
records MIT, ISC, BSD-2-Clause, BSD-3-Clause, Apache-2.0 and Unlicense declarations,
as well as the separately licensed Anthropic packages. The declarations are an
inventory, not a replacement for each package's license text.

When redistributing installed dependencies, retain their original copyright,
LICENSE and applicable NOTICE files and follow their individual terms.
Recheck the installed dependency tree and shipped files when versions change;
optional packages and platform pruning affect what is actually distributed.

## External applications and services

Claude and Codex applications, accounts and services are separate products governed
by their providers' terms. Whoosh's MIT license does not cover them.
