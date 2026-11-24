from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import release


class ReleasePreparation(unittest.TestCase):
    def fixture(self, root):
        (root / "Core").mkdir()
        (root / "release").mkdir()
        (root / "ForeverQuestNavigator.toc").write_bytes(b"## Interface: 1\r\n## Version: 0.2.0\r\nCore\\Locale.lua\r\n")
        (root / "Core/ReleaseNotes.lua").write_text('local Notes = {}\nNotes.history = {\n    {version = "0.2.0", en = "a", de = "b"},\n}\n',
                                                     encoding="utf-8")

    def test_bumps_version_and_creates_files_once(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            previous, created = release.prepare(root, "0.2.1", 'New "thing"\nline', "Neu")
            self.assertEqual(previous, "0.2.0")
            toc = (root / "ForeverQuestNavigator.toc").read_bytes()
            self.assertIn(b"## Version: 0.2.1\r\n", toc)
            self.assertIn("curseforge-changelog-0.2.1.md", created)
            self.assertTrue((root / "release/acceptance-0.2.1.md").read_text(encoding="utf-8").count("- [ ]") >= 2)
            notes = (root / "Core/ReleaseNotes.lua").read_text(encoding="utf-8")
            self.assertLess(notes.index('"0.2.1"'), notes.index('"0.2.0"'))
            self.assertIn('en = "New \\"thing\\"\\nline"', notes)
            (root / "release/curseforge-changelog-0.2.1.md").write_text("# kept", encoding="utf-8")
            with self.assertRaises(ValueError):
                release.prepare(root, "0.2.1")
            _, created = release.prepare(root, "0.2.2")
            self.assertNotIn("ReleaseNotes entry", created)

    def test_rejects_invalid_or_older_versions(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            for version in ("0.2", "0.1.9", "0.2.0", "v0.3.0"):
                with self.assertRaises(ValueError):
                    release.prepare(root, version)


if __name__ == "__main__":
    unittest.main()
