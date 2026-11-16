#!/usr/bin/env python3
"""Seal the credential broker explicitly; ordinary builds only verify and copy it."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

import signing

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "Resources/CredentialBroker"
MANIFEST = STORE / "manifest.json"
NAME = "TrueLCredentialBroker.xpc"
BUNDLE_ID = "com.truel.CredentialBroker"


def sources():
    paths = sorted((ROOT / "Sources/CredentialCore").glob("*.swift"))
    paths += sorted((ROOT / "Helpers/CredentialBroker").glob("*.swift"))
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def tree_digest(path):
    digest = hashlib.sha256()
    for entry in sorted(path.rglob("*")):
        if entry.is_symlink():
            raise RuntimeError("Credential broker must not contain symbolic links")
        if entry.is_file():
            digest.update(str(entry.relative_to(path)).encode() + b"\0" + entry.read_bytes())
    return digest.hexdigest()


def cdhash(path):
    output = signing.run("/usr/bin/codesign", "-dvvv", str(path))
    return re.search(r"^CDHash=([0-9a-f]+)$", output, re.MULTILINE).group(1)


def verify_bundle(bundle, manifest):
    if tree_digest(bundle) != manifest["bundleSHA256"]:
        raise RuntimeError("Credential broker bytes changed; refusing to change its Keychain identity")
    signing.run("/usr/bin/codesign", "--verify", "--strict", "-R=" + manifest["requirement"], str(bundle))
    if cdhash(bundle) != manifest["cdhash"]:
        raise RuntimeError("Credential broker CDHash changed")


def verify():
    if not MANIFEST.exists():
        raise RuntimeError("Missing sealed broker. Run tools/credential_broker.py seal --revision 1 explicitly")
    manifest = json.loads(MANIFEST.read_text())
    if manifest["signerSHA1"] != signing.identity():
        raise RuntimeError("Broker and application use different signing identities")
    if manifest["sources"] != sources():
        raise RuntimeError("Broker source changed. Review and explicitly seal a new revision; never rebuild it during an ordinary release")
    verify_bundle(STORE / NAME, manifest)
    return manifest


def verify_embedded(app):
    manifest = verify()
    verify_bundle(app / "Contents/XPCServices" / NAME, manifest)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("TrueLCredentialBrokerRequirement") != manifest["requirement"]:
        raise RuntimeError("Application does not pin the sealed credential broker")


def embed(app):
    manifest = verify()
    destination = app / "Contents/XPCServices" / NAME
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(STORE / NAME, destination)
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["TrueLCredentialBrokerRequirement"] = manifest["requirement"]
    info_path.write_bytes(plistlib.dumps(info))
    verify_embedded(app)
    print(f"Embedded unchanged credential broker revision {manifest['revision']} ({manifest['cdhash']})")


def seal(revision):
    if revision < 1:
        raise RuntimeError("Revision must be positive")
    if MANIFEST.exists() and revision <= json.loads(MANIFEST.read_text())["revision"]:
        raise RuntimeError("Sealing requires a new revision; an existing credential identity must not be overwritten")
    signing.check()
    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="credential-broker-", dir=ROOT / "build") as folder:
        bundle = Path(folder) / NAME
        executable = bundle / "Contents/MacOS/TrueLCredentialBroker"
        executable.parent.mkdir(parents=True)
        subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-O", "-target", "arm64-apple-macosx26.0",
                        "-module-cache-path", str(ROOT / ".build/modules"),
                        *[str(ROOT / path) for path in sources()], "-o", str(executable)], check=True)
        client = f'identifier "com.truel.prototype" and certificate leaf = H"{signing.identity()}"'
        info = {"CFBundleExecutable": "TrueLCredentialBroker", "CFBundleIdentifier": BUNDLE_ID,
                "CFBundleName": "TrueL Credentials", "CFBundlePackageType": "XPC!",
                "CFBundleVersion": str(revision), "CFBundleShortVersionString": str(revision),
                "TrueLClientRequirement": client,
                "XPCService": {"ServiceType": "Application", "JoinExistingSession": True}}
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        signing.run("/usr/bin/codesign", "--force", "--sign", signing.identity(), "--timestamp=none",
                    "--options", "runtime", "--requirements", "=designated => " + signing.requirement(bundle), str(bundle))
        fingerprint = cdhash(bundle)
        requirement = signing.requirement(bundle) + f' and cdhash H"{fingerprint}"'
        manifest = {"revision": revision, "signerSHA1": signing.identity(), "sources": sources(),
                    "cdhash": fingerprint, "requirement": requirement, "bundleSHA256": tree_digest(bundle)}
        verify_bundle(bundle, manifest)
        STORE.mkdir(parents=True, exist_ok=True)
        destination = STORE / NAME
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(bundle, destination)
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Sealed revision {revision}. Credential continuity must be verified before release.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("seal").add_argument("--revision", type=int, required=True)
    sub.add_parser("verify")
    sub.add_parser("embed").add_argument("app", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "seal": seal(args.revision)
        elif args.command == "embed": embed(args.app)
        else: verify(); print("PASS sealed credential broker")
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"credential broker: {error}")
