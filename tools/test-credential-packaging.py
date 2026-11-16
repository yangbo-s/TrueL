#!/usr/bin/env python3
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch

import credential_broker as broker


class CredentialPackagingTests(unittest.TestCase):
    def test_source_and_signer_changes_stop_embedding(self):
        manifest = json.loads(broker.MANIFEST.read_text())
        with patch.object(broker, "sources", return_value={}):
            with self.assertRaisesRegex(RuntimeError, "source changed"):
                broker.verify()
        with patch.object(broker.signing, "identity", return_value="0" * 40):
            with self.assertRaisesRegex(RuntimeError, "different signing"):
                broker.verify()
        self.assertTrue(manifest["cdhash"])

    def test_changed_binary_and_metadata_are_rejected(self):
        manifest = json.loads(broker.MANIFEST.read_text())
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder) / broker.NAME
            shutil.copytree(broker.STORE / broker.NAME, bundle)
            self.assertEqual(broker.tree_digest(bundle), manifest["bundleSHA256"])
            (bundle / "Contents/Info.plist").write_bytes(b"changed")
            with self.assertRaisesRegex(RuntimeError, "bytes changed"):
                broker.verify_bundle(bundle, manifest)

    def test_component_joins_user_session_and_pins_client_identity(self):
        info = plistlib.loads((broker.STORE / broker.NAME / "Contents/Info.plist").read_bytes())
        self.assertTrue(info["XPCService"]["JoinExistingSession"])
        self.assertEqual(info["XPCService"]["ServiceType"], "Application")
        self.assertIn('identifier "com.truel.prototype"', info["TrueLClientRequirement"])
        self.assertIn(broker.signing.identity(), info["TrueLClientRequirement"])

    def test_existing_revision_cannot_be_silently_resealed(self):
        revision = json.loads(broker.MANIFEST.read_text())["revision"]
        with self.assertRaisesRegex(RuntimeError, "new revision"):
            broker.seal(revision)


if __name__ == "__main__": unittest.main()
