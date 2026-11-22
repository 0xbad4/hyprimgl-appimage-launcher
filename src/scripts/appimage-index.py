#!/usr/bin/env python3
"""List AppImage files as JSON lines with their desktop-entry name and icon.

The directory is read from the APPIMAGE_DIR environment variable and defaults
to ~/Applications.

Output, one JSON object per line:
  {"dir": "<scanned directory>"}
  {"path": "<file>", "name": "<display name>", "icon": "<icon file or empty>"}

Every file is printed once immediately, using cached metadata when present and
the file stem with an empty icon otherwise. Each uncached file is printed a
second time once its metadata has been resolved.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ENV_VAR = "APPIMAGE_DIR"
WORKERS = 4
EXTRACT_TIMEOUT = 15
MAX_ICON_BYTES = 2 * 1024 * 1024
CACHE_DIR = (
    Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    / "hyprimgl"
)
INDEX_FILE = CACHE_DIR / "index.json"


def apps_dir() -> Path:
    return Path(os.environ.get(ENV_VAR) or Path.home() / "Applications").expanduser()


def scan(directory: Path) -> list[Path]:
    try:
        files = [
            p for p in directory.iterdir()
            if p.suffix.lower() == ".appimage" and p.is_file()
        ]
    except OSError:
        return []
    return sorted(files, key=lambda p: p.name.lower())


def cache_key(path: Path) -> str:
    st = path.stat()
    raw = f"{path.resolve()}:{st.st_mtime_ns}:{st.st_size}:{st.st_mode}"
    return hashlib.sha1(raw.encode()).hexdigest()


def load_index() -> dict:
    try:
        data = json.loads(INDEX_FILE.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_index(index: dict) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = INDEX_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(index))
        os.replace(tmp, INDEX_FILE)
    except OSError:
        pass


def locales() -> list[str]:
    lang = os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or ""
    lang = lang.split(".")[0].split("@")[0]
    if not lang:
        return []
    return [lang, lang.split("_")[0]] if "_" in lang else [lang]


def parse_desktop(text: str) -> dict:
    entry: dict[str, str] = {}
    in_entry = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            in_entry = line == "[Desktop Entry]"
            continue
        if in_entry and "=" in line:
            key, value = line.split("=", 1)
            entry[key.strip()] = value.strip()
    return entry


def localized_name(entry: dict) -> str:
    for loc in locales():
        name = entry.get(f"Name[{loc}]")
        if name:
            return name
    return entry.get("Name", "")


def run_extract(path: Path, workdir: str, pattern: str) -> None:
    try:
        subprocess.run(
            [str(path), "--appimage-extract", pattern],
            cwd=workdir,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=EXTRACT_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def fetch(path: Path, workdir: str, root: Path, rel: str) -> Path | None:
    """Extract rel from the image, follow relative symlinks, return the file."""
    cur = root / rel
    if not os.path.lexists(cur):
        run_extract(path, workdir, rel)
    for _ in range(4):
        if not cur.is_symlink():
            break
        target = os.readlink(cur)
        if os.path.isabs(target):
            return None
        nxt = Path(os.path.normpath(cur.parent / target))
        if not str(nxt).startswith(str(root) + os.sep):
            return None
        if not os.path.lexists(nxt):
            run_extract(path, workdir, os.path.relpath(nxt, root))
        cur = nxt
    if cur.is_symlink() or not cur.is_file():
        return None
    return cur


def pick_icon(path: Path, workdir: str, root: Path, icon_name: str, key: str) -> str:
    candidates = [".DirIcon"]
    if icon_name and "/" not in icon_name:
        candidates += [f"{icon_name}.png", f"{icon_name}.svg"]
    for rel in candidates:
        found = fetch(path, workdir, root, rel)
        if found is None or found.stat().st_size > MAX_ICON_BYTES:
            continue
        head = found.read_bytes()[:2048]
        if b"<svg" in head:
            ext = "svg"
        elif head.startswith(b"\x89PNG"):
            ext = "png"
        else:
            continue
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        dest = CACHE_DIR / f"{key}.{ext}"
        shutil.copyfile(found, dest)
        return dest.name
    return ""


def resolve(path: Path, key: str) -> dict:
    name = ""
    icon = ""
    if os.access(path, os.X_OK):
        with tempfile.TemporaryDirectory(prefix="appimg-") as tmp:
            root = Path(tmp) / "squashfs-root"
            run_extract(path, tmp, "*.desktop")
            entry: dict = {}
            for candidate in sorted(root.glob("*.desktop")):
                found = fetch(path, tmp, root, candidate.name)
                if found is None:
                    continue
                parsed = parse_desktop(found.read_text(errors="replace"))
                if parsed.get("Name"):
                    entry = parsed
                    break
            name = localized_name(entry)
            icon = pick_icon(path, tmp, root, entry.get("Icon", ""), key)
    return {"name": name, "icon": icon}


def emit(obj: dict) -> None:
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def emit_app(path: Path, meta: dict | None) -> None:
    meta = meta or {}
    icon = meta.get("icon") or ""
    icon_path = CACHE_DIR / icon if icon else None
    emit({
        "path": str(path),
        "name": meta.get("name") or path.stem,
        "icon": str(icon_path) if icon_path and icon_path.exists() else "",
    })


def prune(index: dict, live_keys: set[str]) -> None:
    stale = [k for k in index if k not in live_keys]
    for key in stale:
        del index[key]
    if CACHE_DIR.is_dir():
        for item in CACHE_DIR.iterdir():
            if item.suffix in (".png", ".svg") and item.stem not in live_keys:
                try:
                    item.unlink()
                except OSError:
                    pass
    if stale:
        save_index(index)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    directory = apps_dir()
    emit({"dir": str(directory)})

    index = load_index()
    keys: dict[Path, str] = {}
    pending: list[Path] = []
    for path in scan(directory):
        try:
            key = cache_key(path)
        except OSError:
            continue
        keys[path] = key
        meta = index.get(key)
        emit_app(path, meta)
        if meta is None:
            pending.append(path)

    if pending:
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            futures = {pool.submit(resolve, p, keys[p]): p for p in pending}
            for future in as_completed(futures):
                path = futures[future]
                try:
                    meta = future.result()
                except Exception:
                    meta = {"name": "", "icon": ""}
                index[keys[path]] = meta
                emit_app(path, meta)
                save_index(index)

    if keys:
        prune(index, set(keys.values()))


if __name__ == "__main__":
    main()
