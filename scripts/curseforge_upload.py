"""Upload a tested tag build to CurseForge; --check-only makes read-only requests."""
import argparse
import json
import os
from pathlib import Path
import re
import sys
from tempfile import TemporaryDirectory
import urllib.error
import urllib.request
from uuid import uuid4

import package

API = "https://wow.curseforge.com/api"
PROJECT_ID = 1812992
GAME_VERSION = "1.60.1"


def release_info(root, tag=None, check_only=False):
    lines = (root / "ForeverQuestNavigator.toc").read_text(encoding="utf-8-sig").splitlines()
    versions = [line.split(":", 1)[1].strip() for line in lines if line.startswith("## Version:")]
    if len(versions) != 1 or not re.fullmatch(r"\d+\.\d+\.\d+", versions[0]):
        raise ValueError("TOC must contain one semantic version")
    version = versions[0]
    if check_only and not tag:
        tag = f"v{version}-beta"
    match = re.fullmatch(r"v" + re.escape(version) + r"(?:-(alpha|beta|rc)(?:\.\d+)?)?", tag or "")
    if not match:
        raise ValueError("A matching explicit version tag is required")
    channel = match[1]
    release_type = "alpha" if channel == "alpha" else "beta" if channel in ("beta", "rc") else "release"
    changelog = root / "release" / f"curseforge-changelog-{version}.md"
    text = changelog.read_text(encoding="utf-8").strip()
    if not text:
        raise ValueError("Version-specific changelog is empty")
    archive = root / "dist" / f"ForeverQuestNavigator-{tag[1:]}.zip"
    # Check the exact artifact against our reproducible, TOC-based package builder.
    with TemporaryDirectory() as temporary:
        expected = package.build(root, Path(temporary), tag)
        if archive.read_bytes() != expected.read_bytes():
            raise ValueError("Upload artifact differs from the validated source package")
    return archive, {"displayName": f"Forever Quest Navigator {tag[1:]}",
                     "releaseType": release_type, "changelogType": "markdown", "changelog": text}


def api_request(path, token, data=None, content_type=None):
    headers = {"X-Api-Token": token, "User-Agent": "ForeverQuestNavigator-release", "Accept": "application/json"}
    if content_type:
        headers["Content-Type"] = content_type
    request = urllib.request.Request(API + path, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # Never echo request headers, tokens or an uncontrolled server response.
        raise ValueError(f"CurseForge API returned HTTP {error.code}") from None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        raise ValueError("CurseForge request failed or returned invalid JSON") from None


def game_version_id(versions):
    if not isinstance(versions, list):
        raise ValueError("Unexpected game-version response")
    matches = [entry.get("id") for entry in versions if isinstance(entry, dict) and entry.get("name") == GAME_VERSION]
    if len(matches) != 1 or type(matches[0]) is not int or matches[0] <= 0:
        raise ValueError(f"Expected exactly one CurseForge WoW version named {GAME_VERSION}; refusing another client version")
    return matches[0]


def multipart(metadata, archive):
    boundary = "FQN-" + uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
            "Content-Type: application/json\r\n\r\n").encode()
    body += json.dumps(metadata, ensure_ascii=False).encode("utf-8")
    body += (f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{archive.name}\"\r\n"
             "Content-Type: application/zip\r\n\r\n").encode()
    body += archive.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    return body, "multipart/form-data; boundary=" + boundary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--tag")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args(argv)
    try:
        archive, metadata = release_info(args.root, args.tag, args.check_only)
        token = os.environ.get("CURSEFORGE_API_TOKEN", "").strip()
        if not token:
            raise ValueError("Repository secret CURSEFORGE_API_TOKEN is missing")
        metadata["gameVersions"] = [game_version_id(api_request("/game/versions", token))]
        print(f"Validated {archive.name}: project {PROJECT_ID}, {metadata['releaseType']}, WoW {GAME_VERSION}")
        if args.check_only:
            print("Read-only configuration check passed; no file uploaded.")
            return 0
        body, content_type = multipart(metadata, archive)
        # Upload exactly once. Do not automatically retry a potentially accepted POST.
        result = api_request(f"/projects/{PROJECT_ID}/upload-file", token, body, content_type)
        if not isinstance(result, dict) or type(result.get("id")) is not int or result["id"] <= 0:
            raise ValueError("Upload response has no file ID; inspect CurseForge before retrying")
        print(f"Uploaded CurseForge file {result['id']}; CurseForge moderation still applies.")
        return 0
    except (ValueError, OSError) as error:
        print(f"CurseForge upload stopped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
