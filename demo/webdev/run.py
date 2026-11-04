#!/usr/bin/env python3
"""ddir · web-dev demo — a portable playbook (macOS / Windows / Linux).

What it does (all window decisions go through `ddir`):
  1. a terminal scaffolds a Vue 3 + Vite + TypeScript project and starts the dev server
  2. VS Code opens the component, the agent rewrites it live (paste in chunks, no IME issues)
  3. Playwright drives real Microsoft Edge: three routed pages, then a design-reference page
  4. Finder/(Explorer) reveals the project folder, Preview/(Photos) shows the mockups
  5. HUD wall, then everything is rolled back so the demo can be played again

The Swift `ddir stage` demo is mac-only; this one is deliberately a *client*: it only uses
ddir's platform-neutral commands (mode/claim/list/close/own/release/hud) plus small per-OS
launch helpers at the bottom, so the same playbook runs on Windows.

usage:
  python3 demo/webdev/run.py              # full run (~80s), rolls back at the end
  python3 demo/webdev/run.py --keep       # leave the stage up
  python3 demo/webdev/run.py --fast       # smoke test with short waits
  python3 demo/webdev/run.py --clean      # drop the previous working copy first
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
WORK = Path(os.environ.get("DDIR_WEBDEV_DIR", Path.home() / "ddir-webdev-demo"))
DDIR = os.environ.get("DDIR_BIN", "ddir")
IS_MAC = sys.platform == "darwin"
IS_WIN = sys.platform.startswith("win")
PORT = int(os.environ.get("DDIR_WEBDEV_PORT", "5173"))
BASE = f"http://127.0.0.1:{PORT}"

opened: list[tuple[str, str]] = []      # (ref, app) windows this demo opened
owned: set[str] = set()
pw_proc: subprocess.Popen | None = None


def log(msg: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    WORK.mkdir(parents=True, exist_ok=True)
    with open(WORK / "webdev-demo.log", "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def sh(cmd: list[str], cwd: Path | None = None, timeout: int = 120,
       check: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=str(cwd) if cwd else None, timeout=timeout,
                          capture_output=True, text=True, check=check)


def ddir(*args: str, timeout: int = 60) -> dict:
    res = sh([DDIR, *args], timeout=timeout)
    out = (res.stdout or "").strip().splitlines()
    for line in reversed(out):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    return {"ok": False, "error": "no_json", "raw": (res.stdout or res.stderr or "")[:200]}


def windows() -> list[dict]:
    res = sh([DDIR, "list"], timeout=30)
    try:
        return json.loads(res.stdout).get("windows", [])
    except Exception:
        return []


def find_window(app: str, title: str, timeout: float = 20.0) -> dict | None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        for w in windows():
            if w["app"].lower() == app.lower() and title.lower() in w["title"].lower():
                return w
        time.sleep(0.25)
    return None


def wait_new(app: str, before: set[str], timeout: float = 25.0) -> dict | None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        for w in windows():
            if w["app"].lower() == app.lower() and w["hwnd"] not in before:
                return w
        time.sleep(0.25)
    return None


def remember(win: dict | None) -> dict | None:
    if win:
        opened.append((win["hwnd"], win["app"]))
        log(f"window {win['app']} · {win['title'][:60]} · {win['hwnd']}")
    return win


def ensure_owned(app: str) -> None:
    if app not in owned:
        ddir("own", "--app", app)
        owned.add(app)


def claim(needs: str) -> dict:
    res = ddir("claim", "--needs", needs, "--force")
    log(f"claim {needs} -> ok={res.get('ok')} assign={len(res.get('assign', []))}")
    return res


def hud(style: str = "toast", seconds: int = 3) -> None:
    args = ["hud", "--seconds", str(seconds)]
    if style == "wall":
        args.insert(1, "--wall")
    subprocess.Popen([DDIR, *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def prune_edge(keep: set[str]) -> None:
    """Close Edge windows from earlier takes (untranslated blank pages, old shop-web tabs)."""
    for w in windows():
        if w["app"].lower() != "microsoft edge" or w["hwnd"] in keep:
            continue
        if "Nova Store" in w["title"] or "Design references" in w["title"]:
            continue
        ensure_owned(w["app"])
        ddir("close", "--window", w["hwnd"])


def prune(app: str, keep: set[str]) -> None:
    """Close extra windows of `app` (Terminal restores old sessions, Edge keeps leftovers)."""
    for w in windows():
        if w["app"].lower() == app.lower() and w["hwnd"] not in keep:
            ensure_owned(w["app"])
            ddir("close", "--window", w["hwnd"])
            opened[:] = [o for o in opened if o[0] != w["hwnd"]]


DISTRACTORS = ["Obsidian", "WeChat", "Steam++", "Dynamic Wallpaper", "DeepSeek Harness",
               "aDrive", "TextEdit", "Preview", "Activity Monitor"]


def clear_stage() -> None:
    """Clean the stage before every take: no stale demo terminals, no leftovers, fewer windows.

    Hidden apps go through `ddir hide` (which records leases), so the normal `ddir release`
    at the end brings them back.
    """
    if IS_MAC:
        # kill the old shells first, then close the windows (a live process would prompt)
        sh(["pkill", "-f", "beat.sh"])
        sh(["pkill", "-f", f"vite.*--port {PORT}"])
        time.sleep(0.6)
        sh(["osascript", "-e", 'tell application "Terminal" to close every window'])
    # close leftover browser windows from a previous take
    for w in windows():
        if w["app"].lower() == "microsoft edge" and ("Nova Store" in w["title"] or "shop-web" in w["title"]):
            ensure_owned(w["app"])
            ddir("close", "--window", w["hwnd"])
    # hide everything that is not part of the story
    for w in windows():
        if w["app"] in DISTRACTORS:
            ensure_owned(w["app"])
            ddir("hide", "--window", w["hwnd"])
    time.sleep(0.4)


def server_up(timeout: float = 60.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(BASE + "/", timeout=2) as r:
                if r.status == 200:
                    return True
        except Exception:
            time.sleep(0.4)
    return False


# ---------------------------------------------------------------- launch helpers

def terminal_script() -> Path:
    ready = WORK / "ready.txt"
    npm_dir = Path(shutil.which("npm") or "/usr/local/bin").parent
    if ready.exists():
        ready.unlink()
    body = f"""#!/bin/bash
set -e
export PATH="{npm_dir}:$PATH"
cd "{WORK}"
rm -rf shop-web
npm create vite@latest shop-web -- --template vue-ts --no-interactive --no-immediate --overwrite < /dev/null
cd shop-web
npm install --prefer-offline --no-audit --no-fund
cp -R "{HERE / 'app'}/." .
rm -rf src/components/HelloWorld.vue
[ -f public/vite.svg ] && rm -f public/vite.svg
echo "READY $(date +%H:%M:%S)" > "{ready}"
npm run dev -- --host 127.0.0.1 --port {PORT}
"""
    path = WORK / "beat.sh"
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)
    return path


def open_terminal() -> dict | None:
    before = {w["hwnd"] for w in windows() if w["app"].lower() == "terminal"}
    if IS_MAC:
        # AppleScript `do script` opens a window without replaying old sessions; Terminal has
        # already been asked for automation permission on this machine.
        sh(["osascript", "-e", f'tell application "Terminal" to do script "bash {terminal_script()}"'])
    elif IS_WIN:
        # Windows: run the same steps in a PowerShell / cmd window
        ps = WORK / "beat.ps1"
        ps.write_text(
            f"$ErrorActionPreference='Stop'\nSet-Location '{WORK}'\n"
            f"if (Test-Path shop-web) {{ Remove-Item -Recurse -Force shop-web }}\n"
            f"npm create vite@latest shop-web -- --template vue-ts --no-interactive --no-immediate --overwrite\n"
            f"Set-Location shop-web\nnpm install --prefer-offline --no-audit --no-fund\n"
            f"Copy-Item -Recurse -Force '{HERE / 'app'}/*' .\n"
            f"Remove-Item -Force src/components/HelloWorld.vue -ErrorAction SilentlyContinue\n"
            f"'READY' | Out-File -Encoding ascii '{WORK / 'ready.txt'}'\n"
            f"npm run dev -- --host 127.0.0.1 --port {PORT}\n",
            encoding="utf-8")
        sh(["cmd", "/c", "start", "powershell", "-NoExit", "-ExecutionPolicy", "Bypass", "-File", str(ps)])
    else:
        sh(["x-terminal-emulator", "-e", str(terminal_script())])
    return remember(wait_new("Terminal" if IS_MAC else "Windows PowerShell", before))


def open_vscode(file: Path) -> dict | None:
    before = {w["hwnd"] for w in windows() if w["app"].lower() == "code"}
    code = "code"
    mac_code = Path("/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")
    if IS_MAC and mac_code.exists():
        code = str(mac_code)
    sh([code, "--new-window", "--disable-workspace-trust", str(file)])
    return remember(wait_new("Code", before))


def open_folder(path: Path) -> dict | None:
    before = {w["hwnd"] for w in windows()}
    sh(["open", str(path)] if IS_MAC else ["explorer", str(path)])
    return remember(wait_new("Finder" if IS_MAC else "explorer", before))


def open_images(paths: list[Path]) -> dict | None:
    before = {w["hwnd"] for w in windows()}
    if IS_MAC:
        sh(["open", "-a", "Preview", *[str(p) for p in paths]])
        return remember(wait_new("Preview", before))
    for p in paths:
        os.startfile(str(p))  # type: ignore[attr-defined]
    time.sleep(2.0)
    return None


def edge_profile() -> Path:
    """Throwaway Edge profile with translation prompts disabled."""
    prof = WORK / "edge-profile"
    prefs = prof / "Default" / "Preferences"
    prefs.parent.mkdir(parents=True, exist_ok=True)
    if not prefs.exists():
        prefs.write_text(json.dumps({"translate": {"enabled": False}, "intl": {"accept_languages": "en-US,en"}}), encoding="utf-8")
    return prof


def open_playwright(urls: list[str], stay: int = 180) -> subprocess.Popen | None:
    global pw_proc
    pw = HERE / "pw"
    if not (pw / "node_modules" / "playwright-core").exists():
        log("installing playwright-core (first run)…")
        sh(["npm", "install", "--no-audit", "--no-fund"], cwd=pw, timeout=600)
    env = dict(os.environ, PW_PROFILE=str(edge_profile()))
    pw_proc = subprocess.Popen(["node", "open.js", json.dumps(urls), str(stay)],
                               cwd=str(pw), env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return pw_proc


def type_text(text: str, chunk: int = 24, delay: float = 0.09) -> None:
    """Paste in small chunks: looks like typing, and is immune to IME state.

    All chunks go through ONE AppleScript / PowerShell call: per-chunk process startup was
    both slow (~0.5 s each) and racy — fast back-to-back pastes dropped characters.
    """
    chunks = [text[i:i + chunk] for i in range(0, len(text), chunk)]
    if IS_MAC:
        def esc(s: str) -> str:
            return s.replace("\\", "\\\\").replace('"', '\\"')
        items = ", ".join('"' + esc(c).replace("\n", "\\n") + '"' for c in chunks)
        script = f"""
set chunks to {{{items}}}
repeat with c in chunks
  set the clipboard to (contents of c)
  tell application "System Events" to keystroke "v" using command down
  delay {delay}
end repeat
"""
        sh(["osascript", "-e", script], timeout=300)
    elif IS_WIN:
        ps = """
param([string[]]$chunks)
Add-Type -AssemblyName System.Windows.Forms
foreach ($c in $chunks) {
  Set-Clipboard -Value $c
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  Start-Sleep -Milliseconds %d
}
""" % int(delay * 1000)
        sh(["powershell", "-NoProfile", "-Command", ps, "-chunks"] + chunks, timeout=300)
    else:
        for c in chunks:
            sh(["xdotool", "type", "--delay", "30", c])
            time.sleep(delay)


def key(combo: str) -> None:
    """Minimal key helper: 'cmd+a', 'cmd+s' (mac) / 'ctrl+a' (win)."""
    if IS_MAC:
        mod, k = combo.split("+")
        code = {"a": "0", "s": "1"}[k]
        flag = {"cmd": "command down", "shift": "shift down"}[mod]
        sh(["osascript", "-e", f'tell application "System Events" to keystroke "{k}" using {flag}'])
    elif IS_WIN:
        mod, k = combo.split("+")
        flag = "^" if mod in ("cmd", "ctrl") else "+"
        sh(["powershell", "-NoProfile", "-Command",
            "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('%s%s')" % (flag, k)])


# ---------------------------------------------------------------- rollback

def rollback(keep: bool = False) -> None:
    global pw_proc
    if keep:
        log("--keep: leaving the stage up")
        return
    if pw_proc:
        try:
            pw_proc.terminate()
            pw_proc.wait(timeout=10)
        except Exception:
            pass
        pw_proc = None
    # stop the dev server first: closing a terminal that still runs a process prompts on macOS
    if IS_MAC:
        sh(["pkill", "-f", "beat.sh"])
        sh(["pkill", "-f", f"vite.*--port {PORT}"])
        time.sleep(0.8)
        sh(["osascript", "-e", 'tell application "Terminal" to close every window'])
    time.sleep(0.4)
    ddir("release")
    for ref, app in opened:
        ensure_owned(app)
        ddir("close", "--window", ref)
        time.sleep(0.15)
    ddir("mode", "off")
    log(f"rollback: closed {len(opened)} windows, mode=off")


# ---------------------------------------------------------------- the playbook

def work_area() -> list[int]:
    d = ddir("displays")
    managed = d.get("managed") or []
    if managed:
        return managed[0]["work"]
    return [0, 25, 1680, 974]


def tile(refs: list[str], gap: int = 14) -> None:
    """Equal-width columns, computed here and applied with explicit `ddir move` calls.

    (Explicit rects beat name-matching `claim` in a scripted demo: no ambiguity when several
    windows share a title prefix, and it reads clearly in the log.)
    """
    refs = [r for r in refs if r]
    if not refs:
        return
    x, y, w, h = work_area()
    n = len(refs)
    col = (w - (n + 1) * gap) // n
    for i, ref in enumerate(refs):
        rect = f"{x + gap + i * (col + gap)},{y + gap},{col},{h - 2 * gap}"
        ddir("move", "--window", ref, "--rect", rect, "--force")
    log(f"tile {n} -> {col}px columns")


def refs_of(app: str, title_part: str = "") -> list[str]:
    return [w["hwnd"] for w in windows()
            if w["app"].lower() == app.lower() and title_part.lower() in w["title"].lower()]


def run(fast: bool, keep: bool) -> None:
    work_scale = 0.15 if fast else 1.0
    sleep = lambda s: time.sleep(s * work_scale)  # noqa: E731

    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "webdev-demo.log").unlink(missing_ok=True)
    log(f"demo start · work={WORK} · platform={sys.platform}")
    if ddir("mode", "semi").get("ok") is False:
        log("ddir not available — aborting")
        return
    clear_stage()

    # 1. terminal: scaffold + install + dev server
    term = open_terminal()
    log("terminal: npm create vite … npm install … npm run dev")
    deadline = time.time() + (90 if fast else 260)
    while time.time() < deadline and not (WORK / "ready.txt").exists():
        time.sleep(0.5)
    if not server_up(timeout=90 if not fast else 30):
        log("dev server did not come up — check the terminal")
        return
    if not (WORK / "shop-web" / "package.json").exists():
        log("project was not created — check the terminal")
        return
    log("dev server ready")
    term_refs = refs_of("Terminal")
    tile(term_refs)
    hud("toast", 3)
    sleep(2)

    # 2. storefront first (placeholder banner), then the component is written -> HMR
    open_playwright([f"{BASE}/#home"], stay=600)
    time.sleep(4)
    edge = [w["hwnd"] for w in windows()
            if w["app"].lower() == "microsoft edge" and "Nova Store" in w["title"]]
    for ref in edge:
        opened.append((ref, "Microsoft Edge"))
    tile(term_refs[:1] + edge[:1])
    sleep(3)

    banner = WORK / "shop-web" / "src" / "components" / "FeatureBanner.vue"
    typed = (HERE / "typed" / "FeatureBanner.vue").read_text(encoding="utf-8")
    log(f"writing {banner.name} ({len(typed)} bytes) — Vite HMR updates the page live")
    banner.write_text(typed, encoding="utf-8")
    hud("toast", 3)
    sleep(3)

    # 3. show the code that produced it
    code_win = open_vscode(banner)
    if not code_win:
        log("VS Code window not found")
        return
    sleep(2.5)
    tile([code_win["hwnd"]] + edge[:1])
    hud("toast", 3)
    sleep(3)

    # 4. Playwright opens the other two routes -> three columns of pages
    open_playwright([f"{BASE}/#products", f"{BASE}/#about"], stay=600)
    time.sleep(4)
    edge = [w["hwnd"] for w in windows()
            if w["app"].lower() == "microsoft edge" and "Nova Store" in w["title"]]
    for ref in edge:
        if (ref, "Microsoft Edge") not in opened:
            opened.append((ref, "Microsoft Edge"))
    tile(edge[:3])
    sleep(3)
    hud("toast", 3)

    # 5. design references + the folder + the mockups
    open_playwright([f"{BASE}/design-refs.html"], stay=600)
    time.sleep(3)
    design = [w["hwnd"] for w in windows()
              if w["app"].lower() == "microsoft edge" and "Design references" in w["title"]]
    for ref in design:
        if (ref, "Microsoft Edge") not in opened:
            opened.append((ref, "Microsoft Edge"))
    folder = open_folder(WORK / "shop-web" / "src")
    shots = sorted((WORK / "shop-web" / "public" / "design").glob("*.png"))
    preview = open_images(shots[:2])
    refs = design[:1] + ([folder["hwnd"]] if folder else []) + ([preview["hwnd"]] if preview else [])
    tile(refs)
    sleep(3)
    hud("wall", 6)
    sleep(6)

    log("finale")
    rollback(keep)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fast", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--clean", action="store_true")
    args = ap.parse_args()
    if args.clean and WORK.exists():
        shutil.rmtree(WORK)
    if args.keep:
        log("note: --keep leaves windows open; use `ddir release` + close them yourself")
    try:
        run(args.fast, args.keep)
    except KeyboardInterrupt:
        log("interrupted")
        rollback(False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
