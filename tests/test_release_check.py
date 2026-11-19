from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import check_release


class ReleaseChecks(unittest.TestCase):
    def fixture(self, root):
        (root / "Core").mkdir()
        (root / "release").mkdir()
        (root / "ForeverQuestNavigator.toc").write_text("## Version: 1.2.3\nCore/Locale.lua\n", encoding="utf-8")
        (root / "Core/Locale.lua").write_text('local english = {\n    Title = "Title",\n}\nlocal german = setmetatable({\n    Title = "Titel",\n}, { __index = english })\n', encoding="utf-8")
        (root / "release/curseforge-changelog-1.2.3.md").write_text("# 1.2.3\nChanges", encoding="utf-8")
        (root / "release/acceptance-1.2.3.md").write_text("# Fixture\n- [x] Client validation fixture", encoding="utf-8")
        for name in ("LICENSE", "README.md"):
            (root / name).write_text("Example", encoding="utf-8")
        (root / "Bindings.xml").write_text("<Bindings/>", encoding="utf-8")

    def test_release_and_beta_tags_require_matching_versions(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            self.assertEqual(check_release.check(root, "v1.2.3"), ("1.2.3", 1))
            self.assertEqual(check_release.check(root, "v1.2.3-beta.1"), ("1.2.3", 1))
            with self.assertRaises(ValueError):
                check_release.check(root, "v1.2.4")

    def test_missing_and_duplicate_translations_fail(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            locale = root / "Core/Locale.lua"
            original = locale.read_text()
            locale.write_text(original.replace('    Title = "Titel",', '    Other = "Titel",'))
            with self.assertRaisesRegex(ValueError, "parity"):
                check_release.check(root)
            locale.write_text(original.replace('    Title = "Titel",', '    Title = "Titel",\n    Title = "Second",'))
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                check_release.check(root)

    def test_changelog_and_bindings_are_required(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / "Bindings.xml").unlink()
            with self.assertRaisesRegex(ValueError, "bindings"):
                check_release.check(root)
            (root / "release/curseforge-changelog-1.2.3.md").write_text("# Wrong version\nChanges")
            with self.assertRaisesRegex(ValueError, "changelog"):
                check_release.check(root)

    def test_stable_publication_is_blocked_until_client_acceptance(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / "release/acceptance-1.2.3.md").write_text("# Fixture\n- [ ] In-game test pending", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "in-game acceptance"):
                check_release.check(root, "v1.2.3")
            self.assertEqual(check_release.check(root, "v1.2.3-rc.1"), ("1.2.3", 1))
