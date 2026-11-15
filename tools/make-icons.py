#!/usr/bin/env python3
"""Compile the native 3A icon and prepare all six approved runtime choices."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
MANIFEST = RESOURCES / ".icon-build.json"
CONFIG = ROOT / "Icon/variants.json"
HELPER = ROOT / "tools/icon-assets.swift"


def run(*args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, args))}\n{result.stdout}{result.stderr}")
    return result.stdout.strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs(config, developer):
    paths = [CONFIG, HELPER, Path(__file__).resolve()]
    for variant in config["variants"]:
        master = ROOT / config["sourceDirectory"] / variant / "AppIcon.icon"
        document = json.loads((master / "icon.json").read_text())
        for group in document["groups"]:
            for layer in group["layers"]:
                if not (master / "Assets" / layer["image-name"]).is_file():
                    raise RuntimeError(f"Missing layer in {variant}: {layer['image-name']}")
        paths.extend(sorted(p for p in master.rglob("*") if p.is_file()))
    paths.extend(sorted(p for p in (ROOT / "Icon/AppIcon.icon").rglob("*") if p.is_file()))
    result = {str(p.relative_to(ROOT)): sha(p) for p in paths}
    # Tool identities invalidate the cache when Xcode changes, without launching
    # the asset compiler on ordinary incremental builds.
    for name, path in {
        "actool": developer / "usr/bin/actool",
        "ictool": developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool",
    }.items():
        stat = path.stat()
        result[f"tool:{name}"] = f"{path}:{stat.st_size}:{stat.st_mtime_ns}"
    result["default"] = config["default"]
    return result


def is_current(fingerprint, expected):
    try:
        manifest = json.loads(MANIFEST.read_text())
        return (manifest["inputs"] == fingerprint and set(manifest["outputs"]) == set(expected)
                and all((RESOURCES / p).is_file() and sha(RESOURCES / p) == digest
                        for p, digest in manifest["outputs"].items()))
    except (OSError, ValueError, KeyError):
        return False


def render(ictool, master, output, rendition="Default"):
    # Icon Composer treats a symlink as a plain file instead of a document bundle.
    run(ictool, master.resolve(), "--export-image", "--output-file", output,
        "--platform", "macOS", "--rendition", rendition,
        "--width", "412", "--height", "412", "--scale", "1")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify source and output hashes without rebuilding")
    parser.add_argument("--force", action="store_true", help="rebuild even when hashes match")
    parser.add_argument("--review", type=Path, help="also render 3A in four macOS appearances into this directory")
    args = parser.parse_args()
    config = json.loads(CONFIG.read_text())
    if config["canvasPixels"] != 512 or config["bodyPixels"] != 412:
        raise RuntimeError("The Dock export contract is 412 px centered in a 512 px canvas")
    master = ROOT / "Icon/AppIcon.icon"
    expected_master = ROOT / config["sourceDirectory"] / config["default"] / "AppIcon.icon"
    # Canonical 3A adds an explicit white backing so native Dark and Clear
    # appearances retain contrast. Its two approved glyph layers stay untouched.
    for name in ["ink.svg", "accent.svg"]:
        if sha(master / "Assets" / name) != sha(expected_master / "Assets" / name):
            raise RuntimeError(f"Canonical {name} differs from the approved {config['default']} master")
    developer = Path(run("xcode-select", "-p"))
    ictool = developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"
    fingerprint = inputs(config, developer)
    expected = ["Assets.car", "AppIcon.icns"]
    for variant in config["variants"]:
        expected.extend([f"AppIcons/{variant}.png", f"AppIcons/{variant}-preview.png"])
    current = is_current(fingerprint, expected)
    if args.check:
        if not current:
            raise RuntimeError("Icon sources or generated assets changed; run tools/make-icons.py")
        print("Icon source and output hashes verified: all six variants; default 3A")
        return
    if current and not args.force and not args.review:
        print("Icon assets are current (six variants; default 3A)")
        return

    with tempfile.TemporaryDirectory(prefix="truel-icons-") as directory:
        work = Path(directory)
        helper = work / "icon-assets"
        run("xcrun", "swiftc", HELPER, "-module-cache-path", work / "ModuleCache", "-o", helper)
        if not current or args.force:
            generated = work / "generated"
            generated.mkdir()
            run("xcrun", "actool", master.resolve(), "--compile", generated, "--platform", "macosx",
                "--minimum-deployment-target", "26.0", "--app-icon", "AppIcon",
                "--output-partial-info-plist", work / "partial.plist",
                "--output-format", "human-readable-text", "--errors", "--warnings")
            if not all((generated / name).is_file() for name in ["Assets.car", "AppIcon.icns"]):
                raise RuntimeError("actool did not produce Assets.car and AppIcon.icns")
            with (work / "partial.plist").open("rb") as file:
                native_info = plistlib.load(file)
            if (native_info.get("CFBundleIconName") != "AppIcon"
                    or native_info.get("CFBundleIconFile") not in ["AppIcon", "AppIcon.icns"]):
                raise RuntimeError(f"Unexpected actool icon metadata: {native_info}")
            (generated / "AppIcons").mkdir()
            for variant in config["variants"]:
                source = ROOT / config["sourceDirectory"] / variant / "AppIcon.icon"
                raw = work / f"{variant}.png"
                render(ictool, source, raw)
                run(helper, "prepare", raw, generated / f"AppIcons/{variant}.png",
                    generated / f"AppIcons/{variant}-preview.png")
            print(run(helper, "validate", *(generated / f"AppIcons/{v}.png" for v in config["variants"])))
            for relative in expected:
                destination = RESOURCES / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(generated / relative, destination.with_suffix(destination.suffix + ".tmp"))
                destination.with_suffix(destination.suffix + ".tmp").replace(destination)
            manifest = {"inputs": fingerprint, "outputs": {p: sha(RESOURCES / p) for p in expected},
                        "nativeInfo": native_info}
            MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
            print("Wrote Resources/Assets.car, AppIcon.icns and six AppIcons + previews (default 3A)")
        else:
            print("Icon assets are current (six variants; default 3A)")
        if args.review:
            review = args.review.resolve()
            review.mkdir(parents=True, exist_ok=True)
            for rendition in ["Default", "Dark", "TintedDark", "ClearLight"]:
                render(ictool, master, review / f"{rendition}.png", rendition)
            run(helper, "sheet", review, review / "3A-native-looks.png")
            print(f"Wrote {review / '3A-native-looks.png'}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        raise SystemExit(f"Icon assets: {error}") from error
