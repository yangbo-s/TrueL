#!/usr/bin/env python3
"""Real login-Keychain/XPC and two Sparkle installs, using disposable fixtures only."""
import functools
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import threading
import time
import tempfile
import uuid
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))
import credential_broker
import signing

ROOT = Path(__file__).resolve().parent.parent
# Sparkle performs atomic filesystem exchanges. Use the local APFS volume,
# rather than a workspace mount that may not implement renamex_np.
RUN = Path(tempfile.mkdtemp(prefix="truel-credential-continuity-", dir="/private/tmp"))
SPARKLE = ROOT / "build/TrueL.app/Contents/Frameworks"
TOOLS = ROOT / ".build/sparkle-tools/bin"
TICKET = str(uuid.uuid4())
DOMAIN = "com.truel.credential-continuity." + TICKET


def run(*args, expect=0, timeout=90):
    result = subprocess.run([str(arg) for arg in args], cwd=ROOT, text=True,
                            capture_output=True, timeout=timeout)
    if result.returncode != expect:
        raise RuntimeError(f"Command failed ({result.returncode}): {Path(str(args[0])).name}\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def compile_probes():
    modules = RUN / "Modules"
    modules.mkdir(parents=True)
    flags = ["xcrun", "swiftc", "-swift-version", "6", "-O", "-module-cache-path", ROOT / ".build/modules"]
    run(*flags, "-parse-as-library", "-whole-module-optimization", "-emit-module", "-emit-object",
        "-module-name", "CredentialCore", *sorted((ROOT / "Sources/CredentialCore").glob("*.swift")),
        "-emit-module-path", modules / "CredentialCore.swiftmodule", "-o", modules / "CredentialCore.o")
    common = [*flags, "-parse-as-library", "-I", modules,
              ROOT / "Sources/TrueL/CredentialBrokerClient.swift", modules / "CredentialCore.o"]
    for version in (1, 2, 3):
        run(*common, "-D", f"PROBE_BUILD_{version}", ROOT / "tools/credentials/Probe.swift", "-o", RUN / f"Probe{version}")
    run(*common, "-F", SPARKLE, "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker",
        "@executable_path/../Frameworks", ROOT / "tools/credentials/UpdateProbe.swift", "-o", RUN / "UpdateProbe")


def make_app(path, executable, extra=None, identifier="com.truel.prototype", framework=False):
    (path / "Contents/MacOS").mkdir(parents=True)
    shutil.copy2(executable, path / "Contents/MacOS/CredentialProbe")
    info = {"CFBundleExecutable": "CredentialProbe", "CFBundleIdentifier": identifier,
            "CFBundleName": "TrueL Credential Check", "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0"}
    info.update(extra or {})
    (path / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    if framework:
        run("/usr/bin/ditto", SPARKLE, path / "Contents/Frameworks")
    credential_broker.embed(path)
    signing.sign(path)
    return path


def probe(app, action, expect=0):
    output = run(app / "Contents/MacOS/CredentialProbe", action, TICKET, expect=expect, timeout=25)
    print(output, flush=True)
    return output


def direct_regression():
    apps = []
    for version in (1, 2):
        executable = RUN / f"Direct{version}"
        run("xcrun", "swiftc", "-module-cache-path", ROOT / ".build/modules", "-D", f"PROBE_BUILD_{version}",
            ROOT / "tools/credentials/DirectProbe.swift", "-o", executable)
        apps.append(make_app(RUN / f"Direct{version}.app", executable, identifier="com.truel.credential-regression"))
    try:
        probe(apps[0], "create")
        probe(apps[0], "read")
        assert "status=-25293" in probe(apps[1], "read", expect=1)
        print("PASS original cross-build Keychain failure reproduced", flush=True)
    finally:
        probe(apps[0], "delete")


def xpc_checks():
    apps = [make_app(RUN / f"Client{version}.app", RUN / f"Probe{version}") for version in (1, 2, 3)]
    hashes = [credential_broker.cdhash(app) for app in apps]
    assert len(set(hashes)) == 3, "Client fingerprints must change between builds"
    try:
        probe(apps[0], "create")
        for app in apps: probe(app, "read")
        wrong_id = make_app(RUN / "WrongID.app", RUN / "Probe1", identifier="com.truel.untrusted")
        assert "-10002" in probe(wrong_id, "read", expect=1)
        wrong_cert = make_app(RUN / "WrongCertificate.app", RUN / "Probe1")
        run("codesign", "--force", "--sign", "-", "--options", "runtime", wrong_cert)
        assert "-10002" in probe(wrong_cert, "read", expect=1)
        wrong_server = make_app(RUN / "WrongServer.app", RUN / "Probe1")
        run("codesign", "--force", "--sign", "-", "--options", "runtime",
            wrong_server / "Contents/XPCServices" / credential_broker.NAME)
        run("codesign", "--force", "--sign", signing.identity(), "--timestamp=none", "--options", "runtime",
            "--requirements", "=designated => " + signing.requirement(wrong_server), wrong_server)
        assert "-10002" in probe(wrong_server, "read", expect=1)
        return apps[0], hashes
    finally:
        probe(apps[0], "delete")


class QuietHTTP(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass


def update_checks(cleanup_app):
    server_root = RUN / "server"
    server_root.mkdir()
    handler = functools.partial(QuietHTTP, directory=str(server_root))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}"
    secret = RUN / "disposable-update-key"
    public = run("xcrun", "swift", "-module-cache-path", ROOT / ".build/modules",
                 ROOT / "tools/credentials/make-test-key.swift", secret)
    report = RUN / "sparkle-events.jsonl"
    installed = RUN / "installed/TrueL Credential Check.app"
    fixtures = []
    process = None
    try:
        for stage in (1, 2, 3):
            app = make_app(RUN / f"stage{stage}/TrueL Credential Check.app", RUN / "UpdateProbe", {
                "CFBundleVersion": str(9000 + stage), "CFBundleShortVersionString": f"0.0.{stage}",
                "TrueLTestStage": stage, "TrueLTestTicket": TICKET, "TrueLTestReport": str(report),
                "SUDefaultsDomain": DOMAIN, "SUFeedURL": f"{url}/stage{stage + 1}.xml", "SUPublicEDKey": public,
                "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
                "SUSignedFeedFailureExpirationInterval": 0, "SUEnableAutomaticChecks": False,
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
            }, framework=True)
            fixtures.append(app)
            if stage == 1: continue
            archive = server_root / f"stage{stage}.zip"
            run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
            signature = run(TOOLS / "sign_update", "--ed-key-file", secret, "-p", archive)
            namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
            ET.register_namespace("sparkle", namespace)
            feed = ET.Element("rss", version="2.0")
            channel = ET.SubElement(feed, "channel")
            ET.SubElement(channel, "title").text = "TrueL isolated credential check"
            item = ET.SubElement(channel, "item")
            ET.SubElement(item, "title").text = f"Fixture {stage}"
            ET.SubElement(item, "{" + namespace + "}version").text = str(9000 + stage)
            ET.SubElement(item, "{" + namespace + "}shortVersionString").text = f"0.0.{stage}"
            ET.SubElement(item, "{" + namespace + "}minimumSystemVersion").text = "26.0"
            ET.SubElement(item, "enclosure", {"url": f"{url}/{archive.name}", "length": str(archive.stat().st_size),
                          "type": "application/octet-stream", "{" + namespace + "}edSignature": signature})
            feed_path = server_root / f"stage{stage}.xml"
            ET.ElementTree(feed).write(feed_path, encoding="utf-8", xml_declaration=True)
            run(TOOLS / "sign_update", "--ed-key-file", secret, feed_path)
        fingerprints = [credential_broker.cdhash(app) for app in fixtures]
        assert len(set(fingerprints)) == 3
        run("/usr/bin/ditto", fixtures[0], installed)
        with (RUN / "sparkle-process.log").open("w") as output:
            process = subprocess.Popen([str(installed / "Contents/MacOS/CredentialProbe")], stdout=output, stderr=output)
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                events = [json.loads(line) for line in report.read_text().splitlines()] if report.exists() else []
                if any(not event["success"] for event in events): raise RuntimeError(f"Sparkle fixture failed: {events}")
                if any(event["stage"] == 3 and event["event"] == "cleanup" for event in events): break
                if process.poll() not in (None, 0): raise RuntimeError("Fixture process failed; inspect sparkle-process.log")
                time.sleep(0.25)
            else: raise RuntimeError("Sparkle install/relaunch timed out; inspect sparkle-events.jsonl")
        assert [event["stage"] for event in events if event["event"] == "credential-read"] == [1, 2, 3]
        assert [event["stage"] for event in events if event["event"] == "install-and-relaunch"] == [1, 2]
        credential_broker.verify_embedded(installed)
        assert plistlib.loads((installed / "Contents/Info.plist").read_bytes())["CFBundleVersion"] == "9003"
        print("PASS two real Sparkle installs and relaunches; credential reads stayed noninteractive", flush=True)
        return fingerprints, events
    finally:
        server.shutdown()
        secret.unlink(missing_ok=True)
        if process and process.poll() is None: process.terminate(); process.wait(timeout=10)
        probe(cleanup_app, "delete")
        subprocess.run(["/usr/bin/defaults", "delete", DOMAIN], capture_output=True)


def main():
    RUN.mkdir(parents=True, exist_ok=True)
    os.chmod(RUN, 0o700)
    print(f"Evidence: {RUN}", flush=True)
    credential_broker.verify_embedded(ROOT / "build/TrueL.app")
    compile_probes()
    direct_regression()
    cleanup_app, client_hashes = xpc_checks()
    update_hashes, events = update_checks(cleanup_app)
    result = {"success": True, "brokerCDHash": credential_broker.verify()["cdhash"],
              "clientCDHashes": client_hashes, "sparkleClientCDHashes": update_hashes, "events": events}
    (RUN / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    evidence = ROOT / "artifacts/credential-continuity" / RUN.name
    evidence.mkdir(parents=True)
    for name in ("result.json", "sparkle-events.jsonl", "sparkle-process.log"):
        shutil.copy2(RUN / name, evidence / name)
    print(f"Saved evidence: {evidence}", flush=True)
    shutil.rmtree(RUN)
    print("PASS credential continuity and peer authentication", flush=True)


if __name__ == "__main__": main()
