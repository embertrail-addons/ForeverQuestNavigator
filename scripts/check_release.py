"""Validate release metadata, translation parity and installable package inputs."""
import argparse
from collections import Counter
from pathlib import Path
import re
from tempfile import TemporaryDirectory
from zipfile import ZipFile

import package


def check(root, tag=None):
    root = Path(root)
    toc = (root / "ForeverQuestNavigator.toc").read_text(encoding="utf-8-sig")
    versions = re.findall(r"^## Version: (\d+\.\d+\.\d+)$", toc, re.M)
    if len(versions) != 1:
        raise ValueError("One semantic TOC version is required")
    version = versions[0]
    if tag and not re.fullmatch(r"v" + re.escape(version) + r"(?:-(alpha|beta|rc)(?:\.\d+)?)?", tag):
        raise ValueError("Tag and TOC version must match")
    if tag == "v" + version:
        acceptance = (root / "release" / f"acceptance-{version}.md").read_text(encoding="utf-8")
        checks = re.findall(r"^- \[([ xX])\]", acceptance, re.M)
        if not checks or any(value == " " for value in checks):
            raise ValueError("Public Release blocked: in-game acceptance checks are still pending")
    changelog = root / "release" / f"curseforge-changelog-{version}.md"
    changes = changelog.read_text(encoding="utf-8").strip()
    if not changes or version not in changes.splitlines()[0]:
        raise ValueError("Version-specific changelog must name the version in its heading")
    locale = (root / "Core/Locale.lua").read_text(encoding="utf-8")
    english, german = locale.split("local german = setmetatable({", 1)
    german = german.split("}, { __index = english })", 1)[0]
    keys = [re.findall(r"^    ([A-Za-z_][A-Za-z_0-9]*)\s*=", block, re.M) for block in (english, german)]
    for language, names in zip(("English", "German"), keys):
        duplicates = [key for key, count in Counter(names).items() if count > 1]
        if duplicates:
            raise ValueError(f"Duplicate {language} translation keys: {', '.join(duplicates)}")
    missing = sorted(set(keys[0]) ^ set(keys[1]))
    if missing:
        raise ValueError("English/German translation parity failed: " + ", ".join(missing))
    with TemporaryDirectory() as temporary:
        archive = package.build(root, Path(temporary), tag)
        with ZipFile(archive) as zipped:
            names = zipped.namelist()
            if zipped.testzip() or "ForeverQuestNavigator/Bindings.xml" not in names:
                raise ValueError("Package is corrupt or missing native key bindings")
            if any(name.startswith(("ForeverQuestNavigator/tests/", "ForeverQuestNavigator/scripts/", "ForeverQuestNavigator/.github/")) for name in names):
                raise ValueError("Development files leaked into package")
    return version, len(keys[0])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--tag")
    args = parser.parse_args()
    try:
        version, translations = check(args.root, args.tag)
        print(f"Release inputs validated: {version}, {translations} keys per language")
    except (ValueError, OSError) as error:
        parser.exit(1, f"Release validation failed: {error}\n")
