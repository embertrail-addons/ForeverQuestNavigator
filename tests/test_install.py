from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import install


class InstallTests(unittest.TestCase):
    def fixture(self, root, body="first"):
        (root / "ForeverQuestNavigator.toc").write_text("## Version: 1.2.3\nCore.lua\n", encoding="utf-8")
        for name in ("LICENSE", "README.md"):
            (root / name).write_text("example", encoding="utf-8")
        (root / "Core.lua").write_text(body, encoding="utf-8")

    def test_replaces_equal_size_files_removes_stale_ones_and_keeps_a_backup(self):
        with TemporaryDirectory() as directory:
            base = Path(directory)
            source, addons, backups = base / "src", base / "AddOns", base / "backups"
            source.mkdir()
            addons.mkdir()
            self.fixture(source, "first")
            first = install.install(source, addons, backups, "a")
            self.assertEqual(first["mismatched"], [])
            target = addons / "ForeverQuestNavigator"
            (target / "Old.lua").write_text("stale", encoding="utf-8")
            self.fixture(source, "fresh")  # same size, different content
            second = install.install(source, addons, backups, "b")
            self.assertEqual((target / "Core.lua").read_text(encoding="utf-8"), "fresh")
            self.assertIn("Old.lua", second["removed"])
            self.assertEqual((backups / "install-b" / "Core.lua").read_text(encoding="utf-8"), "first")
            self.assertEqual(second["version"], "1.2.3")

    def test_missing_addons_folder_fails(self):
        with TemporaryDirectory() as directory:
            base = Path(directory)
            self.fixture(base)
            with self.assertRaises(ValueError):
                install.install(base, base / "missing")


if __name__ == "__main__":
    unittest.main()
