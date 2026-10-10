#!/usr/bin/env python3
"""Opt-in macOS integration check using the configured development identity."""
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True)


with tempfile.TemporaryDirectory(prefix="signing-e2e-") as directory:
    root = Path(directory)
    app = root / "SigningCheck.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Frameworks").mkdir()
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "local.openone.signing-check",
        "CFBundleExecutable": "SigningCheck",
        "CFBundlePackageType": "APPL",
    }))
    source = root / "main.c"
    source.write_text("int answer(void) { return 1; }\n")
    run("/usr/bin/clang", "-dynamiclib", source, "-o", contents / "Frameworks/libOneCore.dylib")
    signatures = []
    for value in (1, 2):
        source.write_text(f"int main(void) {{ return {value}; }}\n")
        run("/usr/bin/clang", source, "-o", contents / "MacOS/SigningCheck")
        run("/usr/bin/python3", ROOT / "scripts/sign-app.py", app)
        result = run("/usr/bin/codesign", "-d", "-r-", "--verbose=4", app)
        details = result.stdout + result.stderr
        requirement = re.search(r"designated => (.+)", details).group(1)
        digest = re.search(r"^CDHash=(.+)$", details, re.M).group(1)
        assert "cdhash" not in requirement, requirement
        assert "anchor" in requirement or "certificate" in requirement, requirement
        signatures.append((requirement, digest))
    assert signatures[0][1] != signatures[1][1], "Fixture binaries must differ"
    assert signatures[0][0] == signatures[1][0], "Identity changed between builds"
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    run("/usr/bin/codesign", "--verify", "-R", "=" + signatures[0][0], app)
    print("PASS: two different binaries retain the same certificate-backed identity.")
    print("PASS: the second binary satisfies the first binary's designated requirement.")
