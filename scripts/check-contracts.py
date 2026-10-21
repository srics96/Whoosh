#!/usr/bin/env python3
"""Portable source/contract checks. These DO NOT compile or execute Swift."""
from pathlib import Path
from urllib.parse import quote, urlparse, parse_qs
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PortableContracts(unittest.TestCase):
    def test_destination_launch_boundaries(self):
        model = (ROOT / "Sources/RelayApp/RelayModel.swift").read_text()
        writer = (ROOT / "Sources/RelayCore/HandoffWriter.swift").read_text()
        self.assertIn("NSWorkspace.shared.open([prepared.deepLink]", model)
        self.assertIn("CodexLink.make(prompt: prepared.bootstrap", model)
        self.assertIn("com.anthropic.claudefordesktop", model)
        self.assertNotIn('appendingPathComponent("claude-link.txt")', writer)

    def test_swift_test_cases_exist(self):
        tests = (ROOT / "Tests/RelayCoreTests/RelayCoreTests.swift").read_text()
        for case in ("testSHA256KnownVectors", "testDeepLinkRoundTripsUnicodeAndReservedCharacters",
                     "testArchivePreservesEveryByteIncludingInvalidUTF8", "testRepositoryCleanFiltersNeverExecute",
                     "testStoppedSourceAndPromptValidationPrecedeWrites", "testRepeatedPreparationNeverOverwritesPackage"):
            self.assertIn("func " + case, tests)

    def test_url_encoding_contract_oracle(self):
        prompt = "Continue café 🌙\nplus+ amp& hash# percent%"
        folder = "/Users/example/Project with spaces+and#symbols"
        url = "claude://code/new?q=" + quote(prompt, safe="-._~") + "&folder=" + quote(folder, safe="-._~")
        parsed = urlparse(url)
        self.assertEqual((parsed.scheme, parsed.netloc, parsed.path), ("claude", "code", "/new"))
        self.assertEqual(parse_qs(parsed.query), {"q": [prompt], "folder": [folder]})
        self.assertIn("%2B", url)
        code = (ROOT / "Sources/RelayCore/ClaudeLink.swift").read_text()
        self.assertIn("maximumPromptUnits = 12_000", code)
        self.assertIn("prompt.utf16.count <= maximumPromptUnits", code)
        self.assertNotIn("file=", code)

    def test_raw_archive_contract_oracle(self):
        original = b'\xef\xbb\xbfSynthetic\r\n\x00\xff  '
        with tempfile.TemporaryDirectory(prefix="relay-contract-") as directory:
            archive = Path(directory) / "original.txt"
            archive.write_bytes(original)
            self.assertEqual(archive.read_bytes(), original)
            self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), hashlib.sha256(original).hexdigest())
        code = (ROOT / "Sources/RelayCore/HandoffWriter.swift").read_text()
        self.assertIn("reread == conversation.data", code)
        self.assertIn("SHA256.hexDigest(reread) == conversation.sha256", code)
        self.assertIn("0o700", code)
        self.assertIn("0o600", code)
        self.assertNotIn("[.atomic, .withoutOverwriting]", code)

    def test_git_capture_is_metadata_only(self):
        code = (ROOT / "Sources/RelayCore/GitSnapshotReader.swift").read_text()
        calls = re.findall(r'command\(\["([^"]+)"', code)
        self.assertEqual(calls, ["rev-parse", "rev-parse", "symbolic-ref"])
        self.assertNotIn('"/bin/sh"', code)
        self.assertNotIn('"/bin/bash"', code)
        self.assertIn('process.arguments = arguments', code)
        self.assertIn('"GIT_OPTIONAL_LOCKS": "0"', code)

    def test_git_metadata_does_not_execute_clean_filter(self):
        with tempfile.TemporaryDirectory(prefix="relay-git-contract-") as directory:
            repo = Path(directory)
            env = {"PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_OPTIONAL_LOCKS": "0"}
            def git(*args):
                return subprocess.run(["/usr/bin/git", "--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", "-C", directory, *args], env=env, check=True, capture_output=True, timeout=8).stdout
            git("init", "-b", "main")
            git("config", "user.name", "Synthetic Test")
            git("config", "user.email", "synthetic@example.invalid")
            (repo / "file.txt").write_text("first\n")
            git("add", ".")
            git("commit", "-m", "Synthetic")
            (repo / ".gitattributes").write_text("file.txt filter=unsafe\n")
            git("config", "filter.unsafe.clean", "touch SHOULD_NOT_EXIST; cat")
            (repo / "file.txt").write_text("other\n")
            git("rev-parse", "--show-toplevel")
            git("rev-parse", "--verify", "HEAD")
            self.assertEqual(git("symbolic-ref", "--quiet", "--short", "HEAD").strip(), b"main")
            self.assertFalse((repo / "SHOULD_NOT_EXIST").exists())

    def test_no_credential_or_private_database_scan(self):
        for path in (ROOT / "Sources").rglob("*.swift"):
            text = path.read_text()
            for forbidden in ('"auth.json"', '".claude"', '".codex/sessions"', 'sqlite3_open', 'CGEventTapCreate'):
                self.assertNotIn(forbidden, text, str(path))

    def test_app_bundle_metadata(self):
        with (ROOT / "Resources/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["CFBundleExecutable"], "Blink")
        self.assertEqual(info["LSMinimumSystemVersion"], "13.0")

    def test_shell_script_syntax(self):
        for script in (ROOT / "scripts").glob("*.sh"):
            subprocess.run(["/bin/bash", "-n", str(script)], check=True)


if __name__ == "__main__":
    print("Portable source/contract checks only. Swift/macOS execution is a separate required gate.")
    unittest.main(verbosity=2)
