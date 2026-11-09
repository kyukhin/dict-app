#!/usr/bin/env python3
"""Build the LibreDict website (spec 0194): texts in Scripts/data/site/<lang>.json
and one HTML template -> site/. `--check` verifies the result (spec Test plan)."""
import html, json, posixpath, re, struct, sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "Scripts/data/site"
SITE = ROOT / "site"
LANGS = ["en", "ru", "es", "ar", "el"]
PAGES = ["index", "privacy", "support"]
EMAIL = "support@libredict.app"
TELEGRAM_URL = "https://t.me/kyukhin"
APP_URL = "https://apps.apple.com/app/id6763217128"
GITHUB_URL = "https://github.com/kyukhin/dict-app"
ALLOWED_HOSTS = {"apps.apple.com", "github.com", "docs.github.com", "t.me"}
SHOTS = ["learn_home_1", "exercise_choice", "drill_question", "definition_greek", "grammar_topic_1"]
MAX_IMAGE = 300 * 1024

TEMPLATE = """<!doctype html>
<html lang="{lang}" dir="{dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<link rel="icon" type="image/png" href="{root}assets/icon.png">
<link rel="stylesheet" href="{root}assets/style.css">
{alternates}</head>
<body>
<header class="bar"><div class="wrap">
<a class="brand" href="{home}"><img src="{root}assets/icon.png" width="28" height="28" alt="">LibreDict</a>
<nav class="langs" aria-label="Language">{langs}</nav>
</div></header>
<main class="wrap">
{body}
</main>
<footer><div class="wrap">
<nav>{footer}</nav>
<p>{open_source}</p>
</div></footer>
</body>
</html>
"""


def rel(src, dst):
    """Relative URL from page `src` to page `dst` (paths like 'ru/index.html')."""
    base = posixpath.dirname(src) or "."
    if dst.endswith("index.html"):
        d = posixpath.dirname(dst) or "."
        r = posixpath.relpath(d, base)
        return "./" if r == "." else r + "/"
    return posixpath.relpath(dst, base)


def page_path(lang, page):
    return f"{page}.html" if lang == "en" else f"{lang}/{page}.html"


def root_of(src):
    return "../" * src.count("/")


def inline(text, subs=None):
    """Escape text; [label](url) becomes a link; {email} and {tg} are filled in."""
    out = html.escape(text, quote=False)
    out = out.replace("{email}", f'<a href="mailto:{EMAIL}">{EMAIL}</a>')
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', out)
    return out.replace("{tg}", TELEGRAM_URL or "")


def body_home(t, src):
    root = root_of(src)
    blocks = "\n".join(f'<section class="block"><h2>{html.escape(b["h"])}</h2><p>{inline(b["p"])}</p></section>'
                       for b in t["blocks"])
    shots = []
    for name, alt in zip(SHOTS, t["shots"]):
        p = SITE / "assets/shots" / t["code"] / f"{name}.png"
        w, h = png_size(p)
        shots.append(f'<li><img src="{root}assets/shots/{t["code"]}/{name}.png" width="{w}" height="{h}" '
                     f'alt="{html.escape(alt)}" loading="lazy"></li>')
    return f"""<section class="hero">
<h1>LibreDict</h1>
<p class="tagline">{html.escape(t["tagline"])}</p>
<p>{html.escape(t["intro"])}</p>
<a class="badge" href="{APP_URL}"><img src="{root}assets/badges/{t["code"]}.svg" width="120" height="40" alt="{html.escape(t["badge_alt"])}"></a>
</section>
<div class="blocks">
{blocks}
</div>
<section>
<h2 class="sr">{html.escape(t["shots_h"])}</h2>
<ul class="shots">
{chr(10).join(shots)}
</ul>
</section>"""


def body_privacy(t, src):
    p = t["privacy"]
    secs = "\n".join(f'<section><h2>{html.escape(s["h"])}</h2>' +
                     "".join(f"<p>{inline(x)}</p>" for x in s["p"]) + "</section>" for s in p["sections"])
    return f'<h1>{html.escape(p["title"])}</h1>\n<p class="muted">{html.escape(p["updated"])}</p>\n{secs}'


def body_support(t, src):
    s = t["support"]
    tg = s["telegram"] if TELEGRAM_URL else ""
    intro = inline(s["intro"].replace("{telegram}", tg))
    faq = "\n".join(f'<section><h3>{html.escape(f["q"])}</h3><p>{inline(f["a"])}</p></section>' for f in s["faq"])
    return f'<h1>{html.escape(s["title"])}</h1>\n<p>{intro}</p>\n<h2>{html.escape(s["faq_h"])}</h2>\n{faq}'


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def render(texts, lang, page):
    t = texts[lang]
    src = page_path(lang, page)
    root = root_of(src)
    key = {"index": "home", "privacy": "privacy", "support": "support"}[page]
    title = {"index": f'LibreDict — {t["tagline"]}',
             "privacy": f'{t["privacy"]["title"]} — LibreDict',
             "support": f'{t["support"]["title"]} — LibreDict'}[page]
    desc = t["description"]
    alts = "".join(f'<link rel="alternate" hreflang="{o}" href="{rel(src, page_path(o, page))}">\n'
                   for o in LANGS if o != lang)
    langs = " ".join(
        f'<a href="{rel(src, page_path(o, page))}" hreflang="{o}" lang="{o}"' +
        (' aria-current="true"' if o == lang else "") + f'>{texts[o]["native"]}</a>' for o in LANGS)
    footer = " ".join([f'<a href="{rel(src, page_path(lang, "privacy"))}">{html.escape(t["nav"]["privacy"])}</a>',
                       f'<a href="{rel(src, page_path(lang, "support"))}">{html.escape(t["nav"]["support"])}</a>',
                       f'<a href="{GITHUB_URL}">GitHub</a>'])
    body = {"index": body_home, "privacy": body_privacy, "support": body_support}[page](t, src)
    return src, TEMPLATE.format(
        lang=lang, dir=t["dir"], title=html.escape(title), description=html.escape(desc), root=root,
        alternates=alts, home=rel(src, page_path(lang, "index")), langs=langs, body=body, footer=footer,
        open_source=html.escape(t["open_source"]))


def build():
    texts = {l: json.loads((DATA / f"{l}.json").read_text(encoding="utf-8")) for l in LANGS}
    for lang in LANGS:
        for page in PAGES:
            src, out = render(texts, lang, page)
            dst = SITE / src
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(out, encoding="utf-8")
    print(f"built {len(LANGS) * len(PAGES)} pages in {SITE}")


class Scan(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags, self.links, self.imgs, self.alts, self.root = [], [], [], [], {}

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.tags.append(tag)
        if tag == "html":
            self.root = a
        if tag == "a" and "href" in a:
            self.links.append(a)
        if tag == "link" and "href" in a:
            (self.alts if a.get("rel") == "alternate" else self.links).append(a)
        if tag == "img":
            self.imgs.append(a)


def check():
    errs = []
    err = errs.append
    for lang in LANGS:
        for page in PAGES:
            src = page_path(lang, page)
            f = SITE / src
            if not f.is_file():
                err(f"missing page {src}")
                continue
            s = Scan()
            s.feed(f.read_text(encoding="utf-8"))
            if s.root.get("lang") != lang:
                err(f"{src}: wrong lang")
            if lang == "ar" and s.root.get("dir") != "rtl":
                err(f"{src}: Arabic page without dir=rtl")
            for bad in ("script", "iframe"):
                if bad in s.tags:
                    err(f"{src}: <{bad}>")
            base = f.parent
            urls = [a["href"] for a in s.links] + [a["href"] for a in s.alts] + [i["src"] for i in s.imgs]
            for u in urls:
                if u.startswith("mailto:"):
                    continue
                if re.match(r"[a-z]+:|//", u):
                    host = re.sub(r"^https://([^/]+).*", r"\1", u)
                    if not u.startswith("https://") or host not in ALLOWED_HOSTS:
                        err(f"{src}: external URL {u}")
                    continue
                target = (base / u.split("#")[0]).resolve()
                if target.is_dir():
                    target = target / "index.html"
                if not target.is_file():
                    err(f"{src}: broken link {u}")
            for o in LANGS:
                if o == lang:
                    continue
                want = (base / rel(src, page_path(o, page))).resolve()
                if want.is_dir():
                    want = want / "index.html"
                for kind, items in (("link", [a["href"] for a in s.links if a.get("hreflang") == o]),
                                    ("hreflang", [a["href"] for a in s.alts if a.get("hreflang") == o])):
                    ok = any(((base / h).resolve() / "index.html" if (base / h).resolve().is_dir()
                              else (base / h).resolve()) == want for h in items)
                    if not ok:
                        err(f"{src}: no {kind} to {o}")
            for i in s.imgs:
                if not (i.get("width") and i.get("height")) and i["src"].endswith(".png"):
                    err(f"{src}: image without width/height {i['src']}")
    for p in (SITE / "assets").rglob("*"):
        if p.is_file() and p.suffix in (".png", ".svg", ".jpg") and p.stat().st_size > MAX_IMAGE:
            err(f"image over 300 KB: {p}")
    for e in errs:
        print("FAIL", e)
    print("check:", "FAILED" if errs else f"OK ({len(LANGS) * len(PAGES)} pages)")
    return 1 if errs else 0


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        sys.exit(check())
    build()
