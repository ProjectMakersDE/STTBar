#!/usr/bin/env python3
"""Run a previously built XCTest bundle without real user data or services."""
from pathlib import Path
import json
import os
import subprocess
import tempfile

base = Path(__file__).resolve().parents[4]
out = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="sttbar-verification-") as temporary:
    root = Path(temporary)
    for name in ("runtime", "install", "home"):
        (root / name).mkdir()
    home = Path.home()
    profile = f'''(version 1)
(allow default)
(deny network*)
(deny file-write* (subpath "{home}/Library"))
(deny file-read* (subpath "{home}/Library/Keychains"))
(deny mach-lookup (global-name "com.apple.securityd"))
(deny mach-lookup (global-name "com.apple.securityd.xpc"))
'''
    (root / "tests.sb").write_text(profile)
    (out / "native-test-sandbox.sb").write_text(profile)
    env = dict(os.environ, STT_RUNTIME_DIR=str(root / "runtime"),
               STT_INSTALL_DIR=str(root / "install"), CFFIXED_USER_HOME=str(root / "home"))
    with (out / "native-tests.log").open("w") as log:
        result = subprocess.run([
            "/usr/bin/sandbox-exec", "-f", str(root / "tests.sb"),
            "/Applications/Xcode.app/Contents/Developer/usr/bin/xctest",
            str(base / "macos-app/.build/debug/STTBarPackageTests.xctest")
        ], cwd=base, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120)
    lines = (out / "native-tests.log").read_text().splitlines()
    summary = [line for line in lines if any(token in line for token in
               ("Executed ", "error:", " failed ", "skipped"))]
    (out / "native-tests.json").write_text(json.dumps({
        "exit_code": result.returncode, "summary": summary
    }, indent=2) + "\n")
    print("\n".join(summary[-2:]))
    raise SystemExit(result.returncode)
