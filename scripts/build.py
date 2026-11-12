#!/usr/bin/env python3
"""Build the zips of the hub and refresh index.json.

  scripts/build.py            build dist/<id>-<version>.zip of every extension, rewrite index.json
  scripts/build.py --check    only verify that index.json matches the sources (exit 1 if not)

An extension is a folder extensions/<id>/ with a manifest.json (id, name, description, version, icon,
type, and optionally apiVersion, requires.sylphrena, requires.apps / requires.optional (programs it needs or can use, as short texts for the user) and system). The index copies from it what Things
shows before installing: apiVersion, requires (which Sylphrena it needs) and system (it asks for
administrator rights). The zip holds that folder (<id>/…, with the executable bits) and is what Sylphrena installs
(Nexus → Extensions → Install from zip) and what Things downloads. Zips are deterministic: the same
sources give the same bytes, so the sha256 in index.json only changes when the sources do.

Releases: the zip of <id> <version> is published as the asset of the release tagged <id>-<version>
(scripts/publish.sh does it), and index.json points there.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "iMacnucintosh/sylphrena-hub"
KINDS = {"extensions": "extension"}  # folder -> kind in the index


def translations(src: Path, m: dict) -> dict:
    """What Things shows before installing (name, description, needs, optional), per language, from the
    extension's own catalogs (i18n/<lang>.json). Only the texts that have a translation."""
    out = {}
    req = m.get("requires") or {}
    for f in sorted((src / "i18n").glob("*.json")):
        cat = json.loads(f.read_text())
        t = {}
        for key, val in (("name", m.get("name")), ("description", m.get("description"))):
            if val and isinstance(cat.get(val), str):
                t[key] = cat[val]
        for key, src_key in (("needs", "apps"), ("optional", "optional")):
            texts = [cat.get(x) for x in req.get(src_key, [])]
            if texts and all(isinstance(x, str) for x in texts):
                t[key] = texts
        if t:
            out[f.stem] = t
    return out


RAW = f"https://raw.githubusercontent.com/{REPO}/main"
SHOT_EXT = {".png", ".jpg", ".jpeg", ".webp"}
MAX_SHOT = 1_500_000  # bytes
LINK_RE = re.compile(r"^https://[^\s]{4,300}$")


def store_doc(src: Path, m: dict) -> dict | None:
    """What Things shows when an extension is opened: long description, highlights, changelog, links and
    screenshots, from extensions/<id>/store/ (details.json, i18n/<lang>.json, screenshots/*). Nothing of it
    goes into the zip. Returns None when the extension has no store/ folder."""
    folder = src / "store"
    if not folder.is_dir():
        return None
    where = f"{src.name}/store"
    d = json.loads((folder / "details.json").read_text())

    def text(v, what, limit):
        if not isinstance(v, str) or not v.strip() or len(v) > limit:
            sys.exit(f"{where}: {what} must be a text of 1–{limit} characters")
        return v.strip()

    doc = {"id": m["id"], "about": text(d.get("about"), "about", 2000)}
    doc["highlights"] = [text(x, "highlight", 160) for x in d.get("highlights", [])][:6]
    doc["author"] = text(d.get("author", "iMacnucintosh"), "author", 80)
    doc["license"] = text(d.get("license", "GPL-3.0"), "license", 40)
    links = {}
    for key, url in (d.get("links") or {}).items():
        if key not in ("source", "issues", "web") or not LINK_RE.match(str(url)):
            sys.exit(f"{where}: link '{key}' must be source, issues or web, and an https URL")
        links[key] = url
    doc["links"] = links
    log = []
    for entry in d.get("changelog", []):
        if not re.match(r"^\d+\.\d+\.\d+$", str(entry.get("version", ""))) or not re.match(r"^\d{4}-\d{2}-\d{2}$", str(entry.get("date", ""))):
            sys.exit(f"{where}: changelog entries need version (x.y.z) and date (YYYY-MM-DD)")
        log.append({"version": entry["version"], "date": entry["date"],
                    "changes": [text(c, "change", 240) for c in entry.get("changes", [])][:12]})
    doc["changelog"] = log
    shots = []
    for shot in d.get("screenshots", [])[:6]:
        f = Path(str(shot.get("file", "")))
        path = folder / "screenshots" / f.name
        # Things only accepts plain names (letters, digits, . _ -): anything else would not be shown
        if f.name != str(f) or not re.fullmatch(r"[A-Za-z0-9._-]{1,100}", f.name) or f.suffix.lower() not in SHOT_EXT or not path.is_file():
            sys.exit(f"{where}: screenshot '{shot.get('file')}' must be an image file in store/screenshots/")
        if path.stat().st_size > MAX_SHOT:
            sys.exit(f"{where}: {f.name} is bigger than {MAX_SHOT // 1000} KB")
        shots.append({"url": f"{RAW}/extensions/{src.name}/store/screenshots/{f.name}", "caption": text(shot.get("caption"), "caption", 160)})
    doc["screenshots"] = shots
    i18n = {}
    for f in sorted((folder / "i18n").glob("*.json")) if (folder / "i18n").is_dir() else []:
        i18n[f.stem] = json.loads(f.read_text())
    doc["i18n"] = i18n
    return doc


def build_zip(src: Path, dst: Path) -> None:
    dst.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        for folder, dirs, files in os.walk(src):
            dirs[:] = sorted(d for d in dirs if d != "__pycache__" and not (Path(folder) == src and d == "store"))
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
                "apiVersion": m.get("apiVersion", 1),
                "requires": (m.get("requires") or {}).get("sylphrena", ""),
                "system": bool((m.get("system") or {}).get("install")),
                "needs": list((m.get("requires") or {}).get("apps", [])),
                "optional": list((m.get("requires") or {}).get("optional", [])),
                "data": list(m.get("data", [])),
                "path": f"{folder}/{src.name}",
                "zip": f"https://github.com/{REPO}/releases/download/{tag}/{zip_path.name}",
                "sha256": hashlib.sha256(data).hexdigest(),
                "size": len(data),
                "i18n": translations(src, m),
                **({"store": f"{RAW}/store/{m['id']}.json"} if (src / "store").is_dir() else {}),
            })
    return out


def store_docs() -> dict[str, str]:
    """store/<id>.json (generated, committed): what Things fetches when an extension is opened."""
    out = {}
    for folder in KINDS:
        for manifest in sorted((ROOT / folder).glob("*/manifest.json")):
            m = json.loads(manifest.read_text())
            doc = store_doc(manifest.parent, m)
            if doc:
                out[m["id"]] = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    return out


def published_changes(items: list[dict]) -> list[str]:
    """Versions that are already in origin/main's index with a different zip: a release is immutable (the
    sha256 of the index must match the published asset), so changing anything inside a zip needs a new version."""
    try:
        old = json.loads(subprocess.run(["git", "show", "origin/main:index.json"], cwd=ROOT, capture_output=True,
                                        text=True, check=True).stdout)
    except (subprocess.CalledProcessError, OSError, ValueError):
        return []  # no origin/main to compare with (a fresh clone of something else): nothing to say
    was = {(i["id"], i["version"]): i["sha256"] for i in old.get("items", [])}
    return [f"{i['id']} {i['version']}" for i in items if (i["id"], i["version"]) in was and was[(i["id"], i["version"])] != i["sha256"]]


def main() -> None:
    index = {
        "schema": 1,
        "name": "Sylphrena Hub",
        "repository": f"https://github.com/{REPO}",
        "items": entries(),
    }
    text = json.dumps(index, indent=2, ensure_ascii=False) + "\n"
    target = ROOT / "index.json"
    docs = store_docs()
    store_dir = ROOT / "store"
    if "--check" in sys.argv:
        changed = published_changes(index["items"])
        if changed:
            sys.exit(f"{', '.join(changed)}: already published with another zip; bump the version in the manifest")
        if not target.exists() or target.read_text() != text:
            sys.exit("index.json is out of date: run scripts/build.py")
        for ext_id, doc in docs.items():
            f = store_dir / f"{ext_id}.json"
            if not f.exists() or f.read_text() != doc:
                sys.exit(f"store/{ext_id}.json is out of date: run scripts/build.py")
        stale = [f.name for f in store_dir.glob("*.json") if f.stem not in docs] if store_dir.is_dir() else []
        if stale:
            sys.exit(f"store/{stale[0]} has no extension: run scripts/build.py")
        print("index.json and store/ are up to date")
        return
    target.write_text(text)
    store_dir.mkdir(exist_ok=True)
    for f in store_dir.glob("*.json"):
        if f.stem not in docs:
            f.unlink()
    for ext_id, doc in docs.items():
        (store_dir / f"{ext_id}.json").write_text(doc)
    for item in index["items"]:
        print(f"{item['id']} {item['version']}  {item['sha256'][:12]}  {item['size']} bytes")


if __name__ == "__main__":
    main()
