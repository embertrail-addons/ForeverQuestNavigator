from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import curseforge_upload as upload


class UploadTests(unittest.TestCase):
    def fixture(self, root, tag="v1.2.3-beta"):
        (root / "ForeverQuestNavigator.toc").write_text("## Version: 1.2.3\nMain.lua\n")
        for name in ("Main.lua", "LICENSE", "README.md"):
            (root / name).write_text("example")
        (root / "release").mkdir()
        (root / "release/curseforge-changelog-1.2.3.md").write_text("Changes")
        return upload.package.build(root, root / "dist", tag)

    def test_tag_channels_and_changelog(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            for tag, channel in (("v1.2.3-alpha.1", "alpha"), ("v1.2.3-beta", "beta"),
                                 ("v1.2.3-rc.2", "beta"), ("v1.2.3", "release")):
                upload.package.build(root, root / "dist", tag)
                _, metadata = upload.release_info(root, tag)
                self.assertEqual(metadata["releaseType"], channel)
                self.assertEqual(metadata["changelog"], "Changes")
            for tag in (None, "v1.2.4", "v1.2.3-beta;echo", "main"):
                with self.assertRaises(ValueError):
                    upload.release_info(root, tag)

    def test_corrupt_artifact_and_missing_changelog_stop_before_network(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            archive = self.fixture(root)
            archive.write_bytes(b"corrupt")
            with self.assertRaises(ValueError):
                upload.release_info(root, "v1.2.3-beta")
            (root / "release/curseforge-changelog-1.2.3.md").unlink()
            with self.assertRaises(OSError):
                upload.release_info(root, "v1.2.3-beta")

    def test_exact_client_version_required(self):
        self.assertEqual(upload.game_version_id([{"name": "1.60.1", "id": 42}]), 42)
        for versions in ([], [{"name": "1.60.2", "id": 42}], [{"name": "1.60.1", "id": "42"}],
                         [{"name": "1.60.1", "id": 1}, {"name": "1.60.1", "id": 2}], {}):
            with self.assertRaises(ValueError):
                upload.game_version_id(versions)

    def test_check_only_never_posts_and_upload_uses_project(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            archive = self.fixture(root)
            calls = []
            def request(path, token, data=None, content_type=None):
                calls.append((path, data))
                self.assertEqual(token, "fake-test-token")
                if path == "/game/versions":
                    return [{"id": 42, "name": "1.60.1"}]
                self.assertIn(archive.read_bytes(), data)
                self.assertIn(b'"gameVersions": [42]', data)
                return {"id": 123}
            with patch.dict(upload.os.environ, {"CURSEFORGE_API_TOKEN": "fake-test-token"}), patch.object(upload, "api_request", request):
                self.assertEqual(upload.main(["--root", directory, "--check-only"]), 0)
                self.assertEqual([p for p, _ in calls], ["/game/versions"])
                calls.clear()
                self.assertEqual(upload.main(["--root", directory, "--tag", "v1.2.3-beta"]), 0)
                self.assertEqual([p for p, _ in calls], ["/game/versions", "/projects/1812992/upload-file"])

    def test_missing_secret_never_calls_api(self):
        with TemporaryDirectory() as directory:
            self.fixture(Path(directory))
            with patch.dict(upload.os.environ, {}, clear=True), patch.object(upload, "api_request") as request:
                self.assertEqual(upload.main(["--root", directory, "--check-only"]), 1)
                request.assert_not_called()

    def test_http_failure_redacts_response_and_never_retries(self):
        error = upload.urllib.error.HTTPError("https://example.invalid", 403, "private response", {}, None)
        with patch.object(upload.urllib.request, "urlopen", side_effect=error) as request:
            with self.assertRaisesRegex(ValueError, "HTTP 403") as raised:
                upload.api_request("/game/versions", "fake-test-token")
            self.assertNotIn("private", str(raised.exception))
            self.assertNotIn("fake-test-token", str(raised.exception))
            self.assertEqual(request.call_count, 1)
            sent = request.call_args[0][0]
            self.assertNotIn("fake-test-token", sent.full_url)
            self.assertEqual(sent.get_header("X-api-token"), "fake-test-token")


if __name__ == "__main__":
    unittest.main()
