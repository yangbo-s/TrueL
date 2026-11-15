#!/usr/bin/env python3
"""Pin one local signing identity across builds. Never silently use ad-hoc signing."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

CONFIG = Path(os.environ.get(
    "TRUEL_SIGNING_CONFIG",
    str(Path.home() / "Library/Application Support/TrueL/Signing/identity.json"),
))


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip())
    return result.stdout + result.stderr


def identity():
    if not CONFIG.exists():
        raise RuntimeError("No pinned signing identity. Run: python3 tools/signing.py setup")
    value = json.loads(CONFIG.read_text())["sha1"].lower()
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise RuntimeError("Invalid signing fingerprint; refusing to change application identity.")
    return value


def identity_kind():
    # Self-signed identities are an explicit local-build choice, never a fallback.
    identity()
    kind = json.loads(CONFIG.read_text()).get("kind")
    if kind not in {"apple", "local-self-signed"}:
        raise RuntimeError("Unknown signing identity kind; run setup with an explicit identity.")
    return kind


def requirement(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    identifier = info["CFBundleIdentifier"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]+", identifier):
        raise RuntimeError("Invalid bundle identifier")
    return f'identifier "{identifier}" and certificate leaf = H"{identity()}"'


def designated(app):
    output = run("/usr/bin/codesign", "-d", "-r-", str(app))
    return next(line.split("designated => ", 1)[1] for line in output.splitlines()
                if "designated => " in line)


def verify(app):
    expected = requirement(app)
    check_requirement = expected
    if identity_kind() == "apple":
        check_requirement = "(" + expected + ") and anchor apple generic"
    run("/usr/bin/codesign", "--verify", "--deep", "--strict",
        "-R=" + check_requirement, str(app))
    if designated(app) != expected:
        raise RuntimeError("Unstable or unexpected designated requirement; refusing this build.")
    details = run("/usr/bin/codesign", "-dvv", str(app))
    if identity_kind() == "apple" and not re.search(r"^TeamIdentifier=[A-Z0-9]{10}$", details, re.MULTILINE):
        raise RuntimeError("Missing Apple Team ID; login-keychain access cannot be stable across updates.")


def sign(app):
    framework = app / "Contents/Frameworks/Sparkle.framework"
    if framework.exists():
        version = framework / "Versions/B"
        # Sign inside-out; preserve the downloader's sandbox entitlements.
        nested = [version / "XPCServices/Downloader.xpc", version / "XPCServices/Installer.xpc",
                  version / "Autoupdate", version / "Updater.app", framework]
        for bundle in nested:
            run("/usr/bin/codesign", "--force", "--sign", identity(), "--timestamp=none",
                "--preserve-metadata=entitlements", str(bundle))
    run("/usr/bin/codesign", "--force", "--sign", identity(), "--timestamp=none",
        "--requirements", "=designated => " + requirement(app), str(app))
    verify(app)


def available_identities(self_signed=False):
    # Local certificates need not be trusted system roots. Do not add root trust.
    args = [] if self_signed else ["-v"]
    output = run("/usr/bin/security", "find-identity", *args, "-p", "codesigning")
    return {fingerprint.lower(): name for fingerprint, name in
            re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', output)
            if self_signed or name.startswith(("Apple Development:", "Mac Developer:", "Developer ID Application:"))}


def check():
    kind = identity_kind()
    if identity() not in available_identities(self_signed=kind == "local-self-signed"):
        raise RuntimeError("Pinned signing identity is unavailable. Restore its certificate and private key; "
                           "refusing to replace it or fall back to ad-hoc signing.")
    print(f"Pinned {kind} signing identity is available.")
    if kind == "local-self-signed":
        print("NOTE: self-signing preserves the designated requirement, but does not guarantee login-keychain access across updates.")


def setup(existing, replace, self_signed):
    if self_signed and not existing:
        raise RuntimeError("Self-signing requires an explicit certificate: setup --self-signed --identity <SHA-1>.")
    available = available_identities(self_signed=self_signed)
    if not available:
        raise RuntimeError("No matching code-signing identity. Import an existing certificate and its private key. "
                           "For local self-signing, use setup --self-signed --identity <SHA-1>.")
    if CONFIG.exists() and not existing and identity() in available:
        check()
        return
    if existing:
        fingerprint = existing.lower()
    elif len(available) == 1:
        fingerprint = next(iter(available))
    else:
        raise RuntimeError("Several identities are available; choose one using setup --identity <SHA-1>.")
    if fingerprint not in available:
        raise RuntimeError("Requested signing identity is not available.")
    kind = "local-self-signed" if self_signed else "apple"
    changes_identity = CONFIG.exists() and (identity() != fingerprint or identity_kind() != kind)
    if changes_identity and not replace:
        raise RuntimeError("A different identity is pinned. Use setup --identity <SHA-1> --replace for a deliberate migration.")
    CONFIG.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if changes_identity:
        CONFIG.with_suffix(".previous.json").write_bytes(CONFIG.read_bytes())
    temporary = CONFIG.with_suffix(".tmp")
    with temporary.open("w") as output:
        json.dump({"sha1": fingerprint, "kind": kind, "name": available[fingerprint]}, output, indent=2)
        output.write("\n")
    temporary.chmod(0o600)
    temporary.replace(CONFIG)
    check()
    print("Identity pinned. No system trust settings or application permissions were changed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    setup_parser = sub.add_parser("setup", help="Pin an existing signing certificate")
    setup_parser.add_argument("--identity", help="SHA-1 of an existing signing certificate")
    setup_parser.add_argument("--replace", action="store_true", help="Explicitly migrate from a previously pinned identity")
    setup_parser.add_argument("--self-signed", action="store_true", help="Explicitly use a local self-signed certificate without system root trust")
    sub.add_parser("check")
    for name in ("sign", "verify"):
        sub.add_parser(name).add_argument("app", type=Path)
    args = parser.parse_args()
    if args.command == "setup":
        setup(args.identity, args.replace, args.self_signed)
    elif args.command == "check":
        check()
    else:
        info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != "com.truel.prototype":
            raise RuntimeError("TrueL's bundle identifier changed; refusing an identity-breaking package.")
        (sign if args.command == "sign" else verify)(args.app.resolve())
        print(f"PASS stable signing: {args.app}")


if __name__ == "__main__":
    os.umask(0o077)
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, StopIteration) as error:
        sys.exit(f"signing: {error}")
