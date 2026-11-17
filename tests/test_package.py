import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from zipfile import ZipFile

spec = importlib.util.spec_from_file_location("package", Path(__file__).resolve().parents[1] / "scripts/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTests(unittest.TestCase):
    def fixture(self, root):
        (root / "ForeverQuestNavigator.toc").write_text("## Version: 1.2.3\nCore.lua\nUI.xml\n", encoding="utf-8")
        for name in ("LICENSE", "README.md", "Core.lua", "Extra.lua"):
            (root / name).write_text("example", encoding="utf-8")
        (root / "UI.xml").write_text('<Ui><Script file="Extra.lua"/></Ui>', encoding="utf-8")
        (root / "development.txt").write_text("exclude me", encoding="utf-8")

    def test_runtime_only_and_reproducible(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            archive = package.build(root, root / "out", "v1.2.3-beta.1")
            first = archive.read_bytes()
            package.build(root, root / "out", "v1.2.3-beta.1")
            self.assertEqual(first, archive.read_bytes())
            with ZipFile(archive) as zip_file:
                self.assertEqual(len(zip_file.namelist()), 6)
                self.assertIn("ForeverQuestNavigator/Extra.lua", zip_file.namelist())
                self.assertNotIn("ForeverQuestNavigator/development.txt", zip_file.namelist())

    def test_mismatched_tag_and_missing_runtime_fail(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            with self.assertRaises(ValueError):
                package.build(root, root / "out", "v2.0.0")
            (root / "Extra.lua").unlink()
            with self.assertRaises(ValueError):
                package.build(root, root / "out")

    def test_path_outside_addon_fails(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            with (root / "ForeverQuestNavigator.toc").open("a", encoding="utf-8") as toc:
                toc.write("../outside.lua\n")
            with self.assertRaises(ValueError):
                package.build(root, root / "out")


if __name__ == "__main__":
    unittest.main()
