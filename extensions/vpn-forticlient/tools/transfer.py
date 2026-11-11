#!/usr/bin/env python3
"""Export / import the FortiClient connections of Sylphrena (extension settings in Nexus).

Both commands read one JSON request on stdin (so the passphrase never reaches argv or the
environment) and print one JSON result on stdout.

export  {"connections": [{"id", "name", "options"}], "secrets": bool, "passphrase": str}
        Writes ~/<Downloads>/forticlient-connections-<date>_<time>.json, or .json.enc when secrets are
        included: then the whole file is encrypted with openssl (AES-256-CBC, PBKDF2) using the
        passphrase. The client certificate (public) is embedded; the password and the client key
        only with secrets. -> {"ok", "path", "count"}

import  {"path": str, "passphrase": str}
        Reads an export (decrypting it if needed). Embedded certificate files are written to
        ~/.config/sylphrena/vpn/certs/<slug>/ (dir 700, key 600) and the options point there.
        -> {"ok", "connections": [{"name", "options", "password"}]} or
           {"ok": false, "needsPassphrase": true} / {"ok": false, "error"}
        The shell then adds or updates the providers and writes each connection file.
"""
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

FORMAT = "sylphrena-forticlient"
VERSION = 1
HOME = Path.home()
VPN_DIR = HOME / ".config" / "sylphrena" / "vpn"
MAX_FILE = 4 * 1024 * 1024
ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")


class Bad(Exception):
    pass


def downloads() -> Path:
    try:
        out = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, timeout=5).stdout.strip()
        if out and Path(out).is_dir() and Path(out) != HOME:
            return Path(out)
    except (OSError, subprocess.SubprocessError):
        pass
    d = HOME / "Downloads"
    d.mkdir(exist_ok=True)
    return d


def openssl(data: bytes, passphrase: str, decrypt: bool) -> bytes:
    r, w = os.pipe()
    os.write(w, passphrase.encode() + b"\n")
    os.close(w)
    args = ["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", "600000", "-salt", "-pass", f"fd:{r}"]
    if decrypt:
        args.append("-d")
    try:
        p = subprocess.run(args, input=data, capture_output=True, pass_fds=(r,), timeout=60)
    finally:
        os.close(r)
    if p.returncode != 0:
        raise Bad("wrong passphrase or damaged file" if decrypt else "openssl failed")
    return p.stdout


def read_password(conn_id: str) -> str:
    if not ID_RE.match(conn_id):
        return ""
    try:
        for line in (VPN_DIR / f"{conn_id}.conf").read_text().splitlines():
            m = re.match(r"^\s*password\s*=\s?(.*)$", line)
            if m:
                return m.group(1)
    except OSError:
        pass
    return ""


def read_text_file(path: str) -> str:
    p = Path(path).expanduser()
    if not path or not p.is_file() or p.stat().st_size > MAX_FILE:
        return ""
    try:
        return p.read_text()
    except (OSError, UnicodeDecodeError):
        return ""


def export(req: dict) -> dict:
    secrets = bool(req.get("secrets"))
    passphrase = req.get("passphrase") or ""
    if secrets and len(passphrase) < 8:
        raise Bad("the passphrase must have at least 8 characters")
    out = []
    for c in req.get("connections") or []:
        options = dict(c.get("options") or {})
        entry = {"name": c.get("name") or "FortiClient", "options": options, "files": {}}
        cert = read_text_file(options.get("userCert", ""))
        if cert:
            entry["files"]["userCert"] = cert
        if secrets:
            key = read_text_file(options.get("userKey", ""))
            if key:
                entry["files"]["userKey"] = key
            entry["password"] = read_password(c.get("id", ""))
        out.append(entry)
    if not out:
        raise Bad("there are no FortiClient connections to export")
    doc = json.dumps({"format": FORMAT, "version": VERSION, "secrets": secrets, "connections": out}, indent=2, ensure_ascii=False).encode()
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    ext = ".json.enc" if secrets else ".json"
    base = downloads()
    path = base / f"forticlient-connections-{stamp}{ext}"
    n = 1
    while path.exists():
        n += 1
        path = base / f"forticlient-connections-{stamp}-{n}{ext}"
    data = openssl(doc, passphrase, False) if secrets else doc
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    return {"ok": True, "path": str(path), "count": len(out)}


def slug(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s[:40] or "connection"


def write_private(path: Path, text: str, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    for d in (VPN_DIR, VPN_DIR / "certs", path.parent):
        os.chmod(d, 0o700)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def import_(req: dict) -> dict:
    path = Path(req.get("path") or "")
    if not path.is_file() or path.stat().st_size > MAX_FILE:
        raise Bad("cannot read the file")
    data = path.read_bytes()
    if data.startswith(b"Salted__"):
        passphrase = req.get("passphrase") or ""
        if not passphrase:
            return {"ok": False, "needsPassphrase": True}
        data = openssl(data, passphrase, True)
    try:
        doc = json.loads(data)
    except ValueError:
        raise Bad("not a FortiClient export")
    if not isinstance(doc, dict) or doc.get("format") != FORMAT or not isinstance(doc.get("connections"), list):
        raise Bad("not a FortiClient export")
    if doc.get("version", 0) > VERSION:
        raise Bad("this export comes from a newer version of the extension")
    result = []
    for c in doc["connections"]:
        if not isinstance(c, dict) or not isinstance(c.get("options"), dict):
            continue
        name = str(c.get("name") or "FortiClient")[:80]
        options = {k: v for k, v in c["options"].items() if isinstance(k, str)}
        files = c.get("files") if isinstance(c.get("files"), dict) else {}
        certs = VPN_DIR / "certs" / slug(name)
        if isinstance(files.get("userCert"), str) and files["userCert"].strip():
            write_private(certs / "client_cert.pem", files["userCert"], 0o644)
            options["userCert"] = str(certs / "client_cert.pem")
        if isinstance(files.get("userKey"), str) and files["userKey"].strip():
            write_private(certs / "client_key.pem", files["userKey"], 0o600)
            options["userKey"] = str(certs / "client_key.pem")
        elif options.get("userKey") and not Path(str(options["userKey"])).is_file():
            # Exported without secrets: the key path of the other PC means nothing here
            options["userKey"] = ""
        result.append({"name": name, "options": options, "password": str(c.get("password") or "")})
    if not result:
        raise Bad("the file has no connections")
    return {"ok": True, "connections": result}


def main() -> None:
    try:
        req = json.loads(sys.stdin.read() or "{}")
        if len(sys.argv) != 2 or sys.argv[1] not in ("export", "import"):
            raise Bad("usage: transfer.py export|import  (request JSON on stdin)")
        res = export(req) if sys.argv[1] == "export" else import_(req)
    except Bad as e:
        res = {"ok": False, "error": str(e)}
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        res = {"ok": False, "error": str(e)}
    print(json.dumps(res, ensure_ascii=False))


if __name__ == "__main__":
    main()
