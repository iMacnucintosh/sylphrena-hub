#!/usr/bin/env python3
"""Build the zips of the hub and refresh index.json.

  scripts/build.py            build dist/<id>-<version>.zip of every extension, rewrite index.json
  scripts/build.py --check    only verify that index.json matches the sources (exit 1 if not)

An extension is a folder extensions/<id>/ with a manifest.json (id, name, description, version, icon,
type). The zip holds that folder (<id>/…, with the executable bits) and is what Sylphrena installs
(Nexus → Extensions → Install from zip) and what Things downloads. Zips are deterministic: the same
sources give the same bytes, so the sha256 in index.json only changes when the sources do.

Releases: the zip of <id> <version> is published as the asset of the release tagged <id>-<version>
(scripts/publish.sh does it), and index.json points there.
"""
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "iMacnucintosh/sylphrena-hub"
KINDS = {"extensions": "extension"}  # folder -> kind in the index


def build_zip(src: Path, dst: Path) -> None:
    dst.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        for folder, dirs, files in os.walk(src):
            dirs[:] = sorted(d for d in dirs if d != "__pycache__")
            for name in sorted(files):
                path = Path(folder) / name
                rel = Path(src.name) / path.relative_to(src)
                info = zipfile.ZipInfo(str(rel), date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (0o100755 if os.access(path, os.X_OK) else 0o100644) << 16
                z.writestr(info, path.read_bytes())


def entries() -> list[dict]:
    out = []
    for folder, kind in KINDS.items():
        for manifest in sorted((ROOT / folder).glob("*/manifest.json")):
            m = json.loads(manifest.read_text())
            src = manifest.parent
            if m["id"] != src.name:
                sys.exit(f"{manifest}: id '{m['id']}' must match the folder name")
            version = m["version"]
            zip_path = ROOT / "dist" / f"{m['id']}-{version}.zip"
            build_zip(src, zip_path)
            data = zip_path.read_bytes()
            tag = f"{m['id']}-{version}"
            out.append({
                "id": m["id"],
                "kind": kind,
                "name": m["name"],
                "description": m.get("description", ""),
                "icon": m.get("icon", "extension"),
                "version": version,
                "path": f"{folder}/{src.name}",
                "zip": f"https://github.com/{REPO}/releases/download/{tag}/{zip_path.name}",
                "sha256": hashlib.sha256(data).hexdigest(),
                "size": len(data),
            })
    return out


def main() -> None:
    index = {
        "schema": 1,
        "name": "Sylphrena Hub",
        "repository": f"https://github.com/{REPO}",
        "items": entries(),
    }
    text = json.dumps(index, indent=2, ensure_ascii=False) + "\n"
    target = ROOT / "index.json"
    if "--check" in sys.argv:
        if not target.exists() or target.read_text() != text:
            sys.exit("index.json is out of date: run scripts/build.py")
        print("index.json is up to date")
        return
    target.write_text(text)
    for item in index["items"]:
        print(f"{item['id']} {item['version']}  {item['sha256'][:12]}  {item['size']} bytes")


if __name__ == "__main__":
    main()
