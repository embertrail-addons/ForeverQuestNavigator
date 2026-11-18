import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("replay", Path(__file__).resolve().parents[1] / "scripts/replay.py")
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)


class ReplayTests(unittest.TestCase):
    def test_strings_are_data(self):
        encoded = replay.lua_data('"); error("injected"); --')
        self.assertNotIn("error", encoded)
        self.assertTrue(encoded.startswith('"\\034'))

    def test_rejects_nonfinite_and_deep_values(self):
        for value in (float("nan"), float("inf"), 10**30):
            with self.assertRaises(ValueError):
                replay.lua_data(value)
        value = 1
        for _ in range(20):
            value = [value]
        with self.assertRaises(ValueError):
            replay.lua_data(value)

    def test_loads_all_committed_cases(self):
        fixtures = Path(__file__).resolve().parent / "fixtures"
        for path in fixtures.glob("*.json"):
            source = replay.replay_source(path)
            self.assertIn("RegressionFixture.Replay", source)

    def test_rejects_unknown_version(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.json"
            path.write_text('{"schema":2}', encoding="utf-8")
            with self.assertRaises(ValueError):
                replay.replay_source(path)


if __name__ == "__main__":
    unittest.main()
