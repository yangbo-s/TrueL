#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('bundle', Path(__file__).with_name('verify-bundle-copy.py'))
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class BundleCopyTests(unittest.TestCase):
    def test_versioned_framework_aliases_and_changed_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ['a', 'b']:
                version = root / name / 'Versions/B'
                version.mkdir(parents=True)
                (version / 'Sparkle').write_bytes(b'framework')
                (root / name / 'Versions/Current').symlink_to('B', target_is_directory=True)
                (root / name / 'Sparkle').symlink_to('Versions/Current/Sparkle')
            self.assertEqual(bundle.manifest(root / 'a'), bundle.manifest(root / 'b'))
            (root / 'b/Versions/B/Sparkle').write_bytes(b'tampered')
            self.assertNotEqual(bundle.manifest(root / 'a'), bundle.manifest(root / 'b'))

    def test_changed_symlink_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'alias').symlink_to('original')
            original = bundle.manifest(root)
            (root / 'alias').unlink()
            (root / 'alias').symlink_to('changed')
            self.assertNotEqual(original, bundle.manifest(root))

    def test_executable_permission_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / 'TrueL'
            binary.write_bytes(b'code')
            binary.chmod(0o644)
            original = bundle.manifest(root)
            binary.chmod(0o755)
            self.assertNotEqual(original, bundle.manifest(root))


if __name__ == '__main__':
    unittest.main()
