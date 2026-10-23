#!/usr/bin/env python3
"""Save Claude Code sessions as raw material for the dev diary.

For each session of this repo it writes, under diary/:
  raw/<date>-<sid8>.txt   the conversation, slimmed to text (local times)
  raw/sessions.json       one row per session: start, end, branch, prompts
  media/<sid8>/           the session's screenshots and recordings, copied out
                          of its /tmp scratchpad, plus any images pasted into chat

Transcripts age out of ~/.claude after 30 days and scratchpads live in /tmp,
so this is what makes the diary possible to write later.

  diary-capture.py --hook       SessionEnd hook; reads the hook's JSON on stdin
  diary-capture.py --backfill   capture every transcript still on disk
  diary-capture.py <path.jsonl> capture one transcript

Re-running is safe: files that are already captured are skipped.
"""
import base64
import glob
import json
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DIARY = REPO / "diary"
RAW = DIARY / "raw"
MEDIA = DIARY / "media"
MEDIA_EXT = {".png", ".jpg", ".jpeg", ".gif", ".heic", ".mp4", ".mov"}
SKIP_PARTS = ("/Build/", "/DerivedData/", ".app/", ".xcassets/", "/Unspool-Assets/", "/venv/",
              "/site-packages/", "/node_modules/", "/thumbs")


def slug(path):
    """The directory name Claude Code uses for a project path."""
    return re.sub(r"[^A-Za-z0-9]", "-", str(path))


def local(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()


def user_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(x.get("text", "") for x in content if isinstance(x, dict) and x.get("type") == "text")
    return ""


def is_prompt(text):
    t = text.lstrip()
    return bool(t) and not t.startswith(("<", "[Request interrupted", "Base directory for this skill"))


def slim(transcript):
    """Text version of the main thread, plus summary facts and pasted images."""
    lines, pasted, times, branches, prompts = [], [], [], [], []
    for raw in open(transcript, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(raw)
        except ValueError:
            continue
        if d.get("isSidechain") or d.get("type") not in ("user", "assistant"):
            continue
        if d.get("isMeta"):
            continue
        ts = d.get("timestamp")
        if not ts:
            continue
        t = local(ts)
        times.append(t)
        if d.get("gitBranch") and d["gitBranch"] not in branches:
            branches.append(d["gitBranch"])
        hm = t.strftime("%m-%d %H:%M")
        who = "USER" if d["type"] == "user" else "CLAUDE"
        content = d.get("message", {}).get("content")
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        if not isinstance(content, list):
            continue
        for x in content:
            if not isinstance(x, dict):
                continue
            kind = x.get("type")
            if kind == "text":
                text = x["text"]
                if who == "USER":
                    if text.startswith("<system-reminder>"):
                        continue
                    if is_prompt(text):
                        prompts.append(text)
                lines.append(f"\n[{hm}] {who}: {text[:6000]}")
            elif kind == "image" and who == "USER":
                src = x.get("source", {})
                if src.get("type") == "base64":
                    pasted.append((t, src.get("media_type", "image/png"), src["data"]))
                lines.append(f"[{hm}] USER <image pasted: chat-{len(pasted):02d}>")
            elif kind == "tool_use":
                inp = x.get("input", {})
                what = inp.get("command") or inp.get("file_path") or inp.get("description") or json.dumps(inp)[:200]
                lines.append(f"[{hm}]   tool {x.get('name')}: {str(what)[:300]}")
            elif kind == "tool_result":
                out = x.get("content")
                if isinstance(out, list):
                    for y in out:
                        if isinstance(y, dict) and y.get("type") == "text":
                            lines.append(f"[{hm}]   -> {y['text'][:400]}")
                        elif isinstance(y, dict) and y.get("type") == "image":
                            lines.append(f"[{hm}]   -> <image>")
                elif isinstance(out, str):
                    lines.append(f"[{hm}]   -> {out[:400]}")
    return lines, pasted, times, branches, prompts


def copy_scratchpad(project_slug, sid, dest):
    """Copy the session's scratchpad screenshots/recordings and pasted-image files."""
    copied = 0
    for root in glob.glob(f"/private/tmp/claude-*/{project_slug}/{sid}"):
        for path in Path(root).rglob("*"):
            p = str(path)
            if not path.is_file() or path.suffix.lower() not in MEDIA_EXT or any(s in p for s in SKIP_PARTS):
                continue
            rel = path.relative_to(root)
            if rel.parts[0] == "images":
                name = "pasted-" + path.name
            elif rel.parts[0] == "scratchpad":
                name = "_".join(rel.parts[1:])
            else:
                name = "_".join(rel.parts)
            target = dest / name
            if target.exists() and target.stat().st_size == path.stat().st_size:
                continue
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            copied += 1
    return copied


def capture(transcript):
    transcript = Path(transcript)
    sid = transcript.stem
    lines, pasted, times, branches, prompts = slim(transcript)
    if not prompts:
        return None
    start, end = min(times), max(times)
    sid8 = sid[:8]
    RAW.mkdir(parents=True, exist_ok=True)
    (RAW / f"{start:%Y-%m-%d}-{sid8}.txt").write_text("\n".join(lines))

    dest = MEDIA / sid8
    copied = copy_scratchpad(transcript.parent.name, sid, dest)
    has_pasted_files = any(dest.glob("pasted-*")) if dest.exists() else False
    if pasted and not has_pasted_files:
        dest.mkdir(parents=True, exist_ok=True)
        for i, (t, mime, data) in enumerate(pasted, 1):
            ext = "jpg" if "jpeg" in mime else mime.split("/")[-1]
            target = dest / f"chat-{i:02d}-{t:%m%d-%H%M}.{ext}"
            if not target.exists():
                target.write_bytes(base64.b64decode(data))
                copied += 1

    index_path = RAW / "sessions.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {}
    index[sid8] = dict(
        session=sid, start=start.isoformat(timespec="minutes"), end=end.isoformat(timespec="minutes"),
        branches=branches, prompts=len(prompts), first_prompt=prompts[0][:200].replace("\n", " "),
        project=transcript.parent.name, media=len(list(dest.glob("*"))) if dest.exists() else 0,
        captured=datetime.now().astimezone().isoformat(timespec="minutes"))
    index_path.write_text(json.dumps(dict(sorted(index.items(), key=lambda kv: kv[1]["start"])), indent=1))
    return sid8, copied


def project_transcripts():
    """Transcripts for this repo and its sibling worktrees (movie-quiz.<branch>)."""
    base = Path.home() / ".claude" / "projects"
    me = slug(REPO)
    for d in sorted(base.glob(me + "*")):
        if d.name == me or d.name.startswith(me + "-"):
            yield from sorted(d.glob("*.jsonl"))


def main():
    args = sys.argv[1:]
    if args == ["--hook"]:
        try:
            event = json.load(sys.stdin)
            if event.get("transcript_path"):
                capture(event["transcript_path"])
        except Exception as e:  # never block a session from ending
            print(f"diary-capture: {e}", file=sys.stderr)
        return 0
    paths = list(project_transcripts()) if args == ["--backfill"] else args
    if not paths:
        print(__doc__)
        return 1
    for p in paths:
        result = capture(p)
        if result:
            print(f"captured {result[0]} (+{result[1]} media)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
