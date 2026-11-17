"""Build an installable addon ZIP from the TOC, without development files."""
import argparse
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo
import xml.etree.ElementTree as ET

ADDON = "ForeverQuestNavigator"


def build(root, output, tag=None, channel=None):
    root, output = Path(root).resolve(), Path(output)
    toc = root / f"{ADDON}.toc"
    lines = toc.read_text(encoding="utf-8-sig").splitlines()
    versions = [line.split(":", 1)[1].strip() for line in lines if line.startswith("## Version:")]
    if len(versions) != 1 or not re.fullmatch(r"\d+\.\d+\.\d+", versions[0]):
        raise ValueError("TOC must contain one semantic Version")
    version = versions[0]
    label = version + (f"-{channel}" if channel else "")
    if tag:
        if not re.fullmatch(r"v" + re.escape(version) + r"(?:-(?:alpha|beta|rc)(?:\.\d+)?)?", tag):
            raise ValueError(f"Tag {tag!r} does not match TOC version {version}")
        label = tag[1:]
    files = set()

    def include(relative):
        relative = relative.replace("\\", "/")
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError(f"Missing or unsafe runtime file: {relative}")
        if path in files:
            return
        files.add(path)
        if path.suffix.lower() == ".xml":
            for node in ET.parse(path).iter():
                reference = node.get("file")
                if reference:
                    include((path.parent / reference.replace("\\", "/")).relative_to(root).as_posix())

    for name in (toc.name, "LICENSE", "README.md"):
        include(name)
    if (root / "Bindings.xml").is_file():
        include("Bindings.xml")
    for line in lines:
        if line.strip() and not line.lstrip().startswith("#"):
            include(line.strip())
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{ADDON}-{label}.zip"
    with ZipFile(archive, "w", ZIP_DEFLATED) as zip_file:
        for path in sorted(files):
            info = ZipInfo(f"{ADDON}/{path.relative_to(root).as_posix()}", (1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            data = path.read_bytes()
            if path.suffix.lower() in {".lua", ".toc", ".xml", ".md"} or path.name == "LICENSE":
                data = data.replace(b"\r\n", b"\n")
            zip_file.writestr(info, data)
    with ZipFile(archive) as zip_file:
        if zip_file.testzip():
            raise ValueError("Archive verification failed")
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, default=Path("dist"))
    parser.add_argument("--tag")
    parser.add_argument("--channel", choices=("alpha", "beta", "rc"))
    args = parser.parse_args()
    try:
        print(build(args.root, args.output, args.tag, args.channel))
    except (ValueError, OSError, ET.ParseError) as error:
        parser.exit(1, f"Package failed: {error}\n")
