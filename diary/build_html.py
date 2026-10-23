"""Build diary/index.html from the chapter files.

    python3 diary/build_html.py

Chapters are the `NN-*.md` files in diary/, each opening with a front-matter block
(id, label, span, versions, accent, order, sessions, start, end). A new chapter
appears on the page without touching this script.

Images: chapters reference originals under media/ (local only, gitignored). The
build writes a downscaled JPEG of every referenced image to web/, which is
committed — web/ is the durable copy. Screen recordings link to media/ and only
play when index.html is opened locally.

Charts come from git (commits, tags), raw/sessions.json (written by
scripts/diary-capture.py) and media/past-builds/ photo names.

Needs the `markdown` package; if it isn't importable, the script makes
diary/.venv, installs it there and re-runs itself.
"""
import html
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent

try:
    import markdown
except ImportError:
    venv = HERE / ".venv"
    py = venv / "bin" / "python"
    # The venv's python symlinks to the system binary, so compare prefixes.
    if py.exists() and Path(sys.prefix).resolve() == venv.resolve():
        sys.exit("markdown is missing from diary/.venv — delete diary/.venv and re-run")
    if not py.exists():
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
        subprocess.run([str(py), "-m", "pip", "install", "-q", "markdown==3.7"], check=True)
    os.execv(str(py), [str(py), __file__, *sys.argv[1:]])


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True).stdout


# ---------- chapters ----------

def front_matter(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}, text
    meta = dict(line.split(": ", 1) if ": " in line else (line.rstrip(":"), "")
                for line in m.group(1).splitlines() if line.strip())
    return meta, text[m.end():]


def chapter_files():
    files = []
    for path in HERE.glob("[0-9][0-9]-*.md"):
        meta, body = front_matter(path.read_text())
        meta.setdefault("id", path.stem)
        meta.setdefault("label", path.stem)
        files.append((float(meta.get("order", path.name[:2])), path, meta, body))
    return sorted(files, key=lambda f: f[0])


def inline_md(text):
    return re.sub(r"^<p>|</p>$", "", markdown.markdown(text.strip()))


def decisions(chapter_id, text, end):
    """Rows of the 4-column table under the chapter's 'Decision log' heading."""
    m = re.search(r"^#+ .*[Dd]ecision log.*$", text, re.M)
    if not m:
        return []
    day = (end or "")[5:10]
    rows = []
    for line in text[m.end():].split("\n"):
        line = line.strip()
        if not line:
            if rows:
                break
            continue
        if not line.startswith("|"):
            break
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line.strip("|"))]
        if len(cells) < 4 or set(cells[0]) <= set("-: ") or cells[1].lower() == "decision":
            continue
        when = cells[0]
        if day and re.match(r"^~?\d{1,2}:\d{2}", when):
            when = f"{day} {when}"
        rows.append(dict(era=chapter_id, when=when, decision=inline_md(cells[1]),
                         why=inline_md(cells[2]), src=inline_md(" | ".join(cells[3:]))))
    return rows


IMG_RE = re.compile(r'<img alt="([^"]*)" src="media/([^"]+)"\s*/?>')
FIG_RE = re.compile(r'<p>\s*((?:<img [^>]+>\s*)+)</p>')


def web_copy(rel):
    """Downscaled JPEG of media/<rel> in web/; returns its path relative to diary/."""
    out = Path("web") / (os.path.splitext(rel)[0] + ".jpg")
    src, dst = HERE / "media" / rel, HERE / out
    if src.exists() and (not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime):
        dst.parent.mkdir(parents=True, exist_ok=True)
        info = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(src)],
                              capture_output=True, text=True).stdout
        w = int(re.search(r"pixelWidth: (\d+)", info)[1])
        h = int(re.search(r"pixelHeight: (\d+)", info)[1])
        size = []
        if h > w and h > 1100:
            size = ["--resampleHeight", "1100"]
        elif w >= h and w > 1400:
            size = ["--resampleWidth", "1400"]
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "72", *size,
                        str(src), "--out", str(dst)], capture_output=True, check=True)
    if not dst.exists():
        print(f"  missing image: media/{rel} (no original, no web copy)")
    return str(out)


def render_chapter(text):
    body = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists"])

    def figs(imgs):
        out = []
        for alt, src in IMG_RE.findall(imgs):
            out.append(
                f'<figure><button class="zoom" type="button" aria-label="Enlarge image">'
                f'<img loading="lazy" src="{web_copy(src)}" alt="{alt}"></button>'
                f'<figcaption>{alt}</figcaption></figure>')
        return "\n".join(out) if out else imgs

    body = FIG_RE.sub(lambda m: figs(m.group(1)), body)
    # Images inside list items or table cells.
    body = IMG_RE.sub(lambda m: figs(m.group(0)), body)
    # Wrap each run of consecutive figures; a lone figure gets the wider solo layout.
    body = re.sub(r'((?:<figure>.*?</figure>\s*)+)',
                  lambda m: '<div class="gallery{}">{}</div>'.format(
                      " solo" if m.group(1).count("<figure>") == 1 else "", m.group(1)),
                  body, flags=re.S)
    body = re.sub(r'<a href="(media/[^"]+\.(?:mp4|mov))">', r'<a class="clip" href="\1" data-clip>', body)
    body = body.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")
    # Fold the long reference lists; the explorer already has every decision.
    body = re.sub(r'<(h[234])>((?:Decision log|Media index)[^<]*)</\1>(.*?)(?=<h[234]>|$)',
                  lambda m: f'<details class="ref"><summary>{m.group(2)}</summary>{m.group(3)}</details>',
                  body, flags=re.S)
    # The chapter header replaces the file's own h2.
    return re.sub(r'^\s*<h2>.*?</h2>', "", body, count=1, flags=re.S)


# ---------- chart data ----------

def commit_series():
    """Per first-parent commit: Swift lines (app/tests), test count, doc words, churn."""
    tags = {git("rev-list", "-1", t).strip(): t for t in git("tag").split()}
    rows = []
    for line in git("log", "--reverse", "--first-parent", "--format=%H|%h|%ad|%s",
                    "--date=format:%Y-%m-%dT%H:%M").strip().split("\n"):
        full, short, when, subject = line.split("|", 3)
        app = tests = ntest = docs = 0
        for f in git("ls-tree", "-r", "--name-only", full).split("\n"):
            if f.endswith(".swift"):
                body = git("show", f"{full}:{f}")
                n = sum(1 for l in body.split("\n") if l.strip())
                if f.startswith("movie-quizTests"):
                    tests += n
                    ntest += len(re.findall(r"@Test\b|func test\w*\(", body))
                else:
                    app += n
            elif f.endswith(".md") and (f.startswith("docs/") or f in ("CLAUDE.md", "CHANGELOG.md")):
                docs += len(git("show", f"{full}:{f}").split())
        stat = git("show", "--shortstat", "--format=", "--first-parent", full)
        ins, dele = re.search(r"(\d+) insertion", stat), re.search(r"(\d+) deletion", stat)
        rows.append(dict(sha=short, date=when, subject=subject, app=app, tests=tests, ntest=ntest,
                         docs=docs, ins=int(ins[1]) if ins else 0, dele=int(dele[1]) if dele else 0,
                         tag=tags.get(full)))
    return rows


def all_commits():
    out = []
    for line in git("log", "--reverse", "--no-merges", "--format=%h|%ad|%s",
                    "--date=format:%Y-%m-%dT%H:%M").strip().split("\n"):
        h, d, s = line.split("|", 2)
        out.append(dict(sha=h, date=d, subject=s))
    return out


def tags():
    out = []
    for line in git("tag", "--list", "v*", "--format=%(refname:short)|%(creatordate:format:%Y-%m-%dT%H:%M)").split():
        name, when = line.split("|")
        commit_date = git("log", "-1", "--format=%ad", "--date=format:%Y-%m-%dT%H:%M", name).strip()
        out.append(dict(name=name[1:], date=commit_date or when))
    return sorted(out, key=lambda t: t["date"])


def sessions(chapters):
    path = HERE / "raw" / "sessions.json"
    if not path.exists():
        return []
    era_of = {}
    for _, _, meta, _ in chapters:
        for sid in meta.get("sessions", "").split():
            era_of[sid] = meta["id"]
    out = []
    for sid8, s in json.loads(path.read_text()).items():
        out.append(dict(sid=sid8, start=s["start"][:16], end=s["end"][:16], prompt=s["first_prompt"][:90],
                        prompts=s["prompts"], era=era_of.get(sid8)))
    return out


def photos():
    seen, out = set(), []
    for p in sorted((HERE / "media" / "past-builds").glob("*-20*")) + sorted((HERE / "web" / "past-builds").glob("*-20*")):
        m = re.search(r"(PHOTO|VIDEO)-(\d{4}-\d{2}-\d{2})-(\d{2})-(\d{2})", p.name)
        if m and (m[2], m[3]) not in seen:
            seen.add((m[2], m[3]))
            out.append(dict(date=f"{m[2]}T{m[3]}:{m[4]}", kind=m[1].lower()))
    return out


def quiet_gaps(commits, min_days=14):
    days = sorted({date.fromisoformat(c["date"][:10]) for c in commits})
    return [dict(start=str(a + timedelta(days=1)), end=str(b - timedelta(days=1)), days=(b - a).days - 1)
            for a, b in zip(days, days[1:]) if (b - a).days - 1 >= min_days]


# ---------- page ----------

def main():
    chapters = chapter_files()
    rendered, all_decisions, n_images = [], [], 0
    for _, path, meta, text in chapters:
        title = re.search(r"^## (.+)$", text, re.M)
        title = re.sub(r"^(Era|Photo record):\s*", "", title[1]) if title else meta["label"]
        all_decisions += decisions(meta["id"], text, meta.get("end"))
        n_images += len(set(re.findall(r"\]\(media/[^)]+\.(?:png|jpg|PNG|jpeg|JPG)\)", text)))
        rendered.append(dict(meta=meta, title=html.escape(title), body=render_chapter(text)))

    commits = all_commits()
    data = dict(
        series=commit_series(), commits=commits, tags=tags(), photos=photos(), gaps=quiet_gaps(commits),
        sessions=sessions(chapters), decisions=all_decisions,
        range=[commits[0]["date"][:10], max(commits[-1]["date"][:10], str(date.today()))],
        eras={c["meta"]["id"]: dict(label=c["meta"]["label"], accent=c["meta"].get("accent", "blue"),
                                    start=c["meta"].get("start", ""), end=c["meta"].get("end", "")[:10],
                                    band=c["meta"].get("band", "yes") != "no") for c in rendered})
    first, last = date.fromisoformat(data["range"][0]), date.fromisoformat(data["range"][1])
    fmt = lambda d: f"{d:%b} {d.day}"
    stats = dict(COMMITS=len(commits), DAYS=len({c["date"][:10] for c in commits}),
                 DECISIONS=len(all_decisions), IMAGES=n_images, TESTS=data["series"][-1]["ntest"],
                 SWIFT=f'{data["series"][-1]["app"]:,}', VERSIONS=len(data["tags"]),
                 VERSION_SPAN=f'{data["tags"][0]["name"]} → {data["tags"][-1]["name"]}' if data["tags"] else "",
                 RANGE=f"{fmt(first)} – {fmt(last)}, {last.year}")

    nav = "".join(f'<a href="#{c["meta"]["id"]}" class="chip {c["meta"].get("accent", "blue")}">{c["meta"]["label"]}</a>'
                  for c in rendered)
    chapter_html = "".join(
        f'''<section class="chapter" id="{c["meta"]["id"]}">
  <header class="chapter-head {c["meta"].get("accent", "blue")}">
    <p class="eyebrow">{c["meta"].get("span", "")} · <span class="ver">{c["meta"].get("versions", "")}</span></p>
    <h2>{c["title"]}</h2>
  </header>
  <div class="prose">{c["body"]}</div>
</section><div class="strip" aria-hidden="true"></div>''' for c in rendered)

    page = (HERE / "template.html").read_text()
    page = page.replace("{{NAV}}", nav).replace("{{CHAPTERS}}", chapter_html)
    page = page.replace("{{DATA}}", json.dumps(data).replace("</", "<\\/"))
    for key, value in stats.items():
        page = page.replace("{{STATS_" + key + "}}", str(value))
    (HERE / "index.html").write_text(page)
    print(f"wrote diary/index.html — {len(rendered)} chapters, {len(all_decisions)} decisions, "
          f"{n_images} images, {len(data['sessions'])} sessions")


if __name__ == "__main__":
    main()
