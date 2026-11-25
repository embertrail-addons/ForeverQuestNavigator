"""Build the addon package and install it into a local WoW AddOns folder.

Copies every file (no timestamp shortcuts: the package uses fixed timestamps, so
tools like robocopy would skip changed files of equal size), removes files that
are no longer in the package, keeps a backup and verifies every file by SHA-256.

Example:
    python scripts/install.py --addons "D:\\Games\\World of Warcraft\\_forever_\\Interface\\AddOns"
The AddOns folder can also come from the environment variable FQN_ADDONS_DIR.
"""
import argparse
from datetime import datetime
import hashlib
import os
from pathlib import Path
import shutil
import sys
from tempfile import TemporaryDirectory
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package  # noqa: E402

ADDON = package.ADDON


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def install(root, addons_dir, backup_root=None, stamp=None):
    root, addons_dir = Path(root), Path(addons_dir)
    if not addons_dir.is_dir():
        raise ValueError(f"AddOns folder not found: {addons_dir}")
    target = addons_dir / ADDON
    result = {"backup": None, "copied": 0, "removed": [], "mismatched": []}
    with TemporaryDirectory() as directory:
        archive = package.build(root, Path(directory) / "dist")
        stage = Path(directory) / "stage"
        with ZipFile(archive) as zip_file:
            zip_file.extractall(stage)
        source = stage / ADDON
        if target.exists() and backup_root is not None:
            backup = Path(backup_root) / f"install-{stamp or datetime.now().strftime('%Y%m%d-%H%M%S')}"
            shutil.copytree(target, backup)
            result["backup"] = backup
        target.mkdir(parents=True, exist_ok=True)
        wanted = set()
        for path in sorted(source.rglob("*")):
            if path.is_file():
                relative = path.relative_to(source)
                wanted.add(relative)
                destination = target / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, destination)
                result["copied"] += 1
        for path in sorted(target.rglob("*"), reverse=True):
            relative = path.relative_to(target)
            if path.is_file() and relative not in wanted:
                path.unlink()
                result["removed"].append(relative.as_posix())
            elif path.is_dir() and not any(path.iterdir()):
                path.rmdir()
        for relative in sorted(wanted):
            if digest(source / relative) != digest(target / relative):
                result["mismatched"].append(relative.as_posix())
        result["version"] = archive.stem.split("-", 1)[1]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--addons", default=os.environ.get("FQN_ADDONS_DIR"), help="WoW Interface\\AddOns folder")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--no-backup", action="store_true")
    args = parser.parse_args()
    if not args.addons:
        parser.exit(1, "Give --addons or set FQN_ADDONS_DIR.\n")
    backups = None if args.no_backup else Path(args.root) / ".local" / "backups"
    try:
        result = install(args.root, args.addons, backups)
    except ValueError as error:
        parser.exit(1, f"Install failed: {error}\n")
    print(f"Installed {ADDON} {result['version']}: {result['copied']} files")
    if result["backup"]:
        print(f"Backup: {result['backup']}")
    for name in result["removed"]:
        print(f"removed stale {name}")
    if result["mismatched"]:
        parser.exit(1, "Verification failed for: " + ", ".join(result["mismatched"]) + "\n")
    print("All files verified by SHA-256. Use /reload, or restart WoW if the TOC or file list changed.")


if __name__ == "__main__":
    main()
