"""Replay an anonymized /fqn fixture export with Lua 5.1 (no game needed)."""
import argparse
import json
import math
from pathlib import Path
import subprocess
import tempfile


def lua_data(value, depth=0):
    if depth > 16:
        raise ValueError("Fixture nesting exceeds limit")
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        if not math.isfinite(value) or abs(value) > 1e15:
            raise ValueError("Invalid numeric value")
        return repr(value)
    if isinstance(value, str):
        # Decimal byte escapes cannot execute user-supplied Lua code.
        return '"' + ''.join(f"\\{byte:03d}" for byte in value.encode("utf-8")) + '"'
    if isinstance(value, list):
        return "{" + ",".join(lua_data(item, depth + 1) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join(f"[{lua_data(key, depth + 1)}]={lua_data(item, depth + 1)}" for key, item in value.items()) + "}"
    raise ValueError("Unsupported value")


def replay_source(path):
    if path.stat().st_size > 1_000_000:
        raise ValueError("Fixture exceeds 1 MB")
    fixture = json.loads(path.read_text(encoding="utf-8-sig"))
    if fixture.get("schema") != 1:
        raise ValueError("Unsupported fixture version")
    if len(fixture.get("quests", [])) > 1000:
        raise ValueError("Too many quests")
    return '''local addon = {}
for _, file in ipairs({"Core/Locale.lua", "Navigation/QuestPrioritizer.lua", "Navigation/TravelSupport.lua", "Core/RegressionFixture.lua"}) do
    assert(loadfile(file))("ForeverQuestNavigator", addon)
end
assert(addon.RegressionFixture.Replay(''' + lua_data(fixture) + '''))
print("PASS regression fixture")
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--lua", default="lua5.1")
    args = parser.parse_args()
    source = replay_source(args.fixture)
    with tempfile.TemporaryDirectory(prefix="fqn-replay-") as directory:
        script = Path(directory) / "replay.lua"
        script.write_text(source, encoding="utf-8")
        subprocess.run([args.lua, str(script)], cwd=Path(__file__).resolve().parents[1], check=True)


if __name__ == "__main__":
    main()
