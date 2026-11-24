"""Prepare a new version: bump the TOC, create changelog, acceptance and validation
files and add the in-game update notes. Nothing is committed, tagged or uploaded.

Example:
    python scripts/release.py 0.2.1 --en "• New thing." --de "• Neues Ding."
"""
import argparse
from pathlib import Path
import re


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def read(path):
    raw = path.read_bytes().decode("utf-8-sig")  # read_text would hide CRLF
    return raw.replace("\r\n", "\n"), "\r\n" in raw


def write(path, text, crlf):
    path.write_text(text.replace("\n", "\r\n") if crlf else text, encoding="utf-8", newline="")


def version_tuple(version):
    return tuple(int(part) for part in version.split("."))


def prepare(root, version, english=None, german=None):
    root = Path(root)
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Version must look like 1.2.3")
    toc_path = root / "ForeverQuestNavigator.toc"
    toc, crlf = read(toc_path)
    current = re.search(r"^## Version: (\d+\.\d+\.\d+)$", toc, re.M)
    if not current:
        raise ValueError("TOC has no semantic version")
    if version_tuple(version) <= version_tuple(current.group(1)):
        raise ValueError("New version %s must be greater than %s" % (version, current.group(1)))
    write(toc_path, toc.replace(current.group(0), "## Version: " + version), crlf)

    release = root / "release"
    created = []
    files = {
        "curseforge-changelog-%s.md" % version: "# Forever Quest Navigator %s\n\n## Changes\n\n- \n\n## Manual checks still open\n\n- \n" % version,
        "acceptance-%s.md" % version: ("# Regular release authorization — %s\n\n"
                                        "- [ ] The user has tested %s in the real client, or explicitly accepted publishing with open manual checks.\n"
                                        "- [ ] The user has explicitly requested publication of %s.\n"
                                        "- [x] Publish as a regular Release only. No alpha, beta or release-candidate publication.\n"
                                        "- [ ] Automated validation passed (see validation-%s.md).\n\n"
                                        "Pending boxes block a tagged release in scripts/check_release.py.\n") % (version, version, version, version),
        "validation-%s.md" % version: "# Local validation — %s\n\n- Lua 5.1 tests: \n- Python tests: \n- Regression fixtures: \n- Release inputs: \n" % version,
    }
    for name, content in files.items():
        path = release / name
        if not path.exists():
            path.write_text(content, encoding="utf-8")
            created.append(name)

    if english and german:
        notes_path = root / "Core" / "ReleaseNotes.lua"
        notes, notes_crlf = read(notes_path)
        if ('version = "%s"' % version) not in notes:
            entry = '    {version = "%s",\n        en = %s,\n        de = %s},\n' % (version, lua_string(english), lua_string(german))
            anchor = "Notes.history = {\n"
            if anchor not in notes:
                raise ValueError("Core/ReleaseNotes.lua has no history table")
            write(notes_path, notes.replace(anchor, anchor + entry, 1), notes_crlf)
            created.append("ReleaseNotes entry")
    return current.group(1), created


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--en", help="English in-game update note (use \\n for new lines)")
    parser.add_argument("--de", help="German in-game update note")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    args = parser.parse_args()
    english = args.en.replace("\\n", "\n") if args.en else None
    german = args.de.replace("\\n", "\n") if args.de else None
    if bool(english) != bool(german):
        parser.exit(1, "Give both --en and --de, or neither.\n")
    try:
        previous, created = prepare(args.root, args.version, english, german)
    except ValueError as error:
        parser.exit(1, "Release preparation failed: %s\n" % error)
    print("Version %s -> %s" % (previous, args.version))
    for name in created:
        print("created " + name)
    print("Next: fill in the changelog and validation, run the tests, then commit.")


if __name__ == "__main__":
    main()
