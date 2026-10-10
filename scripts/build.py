#!/usr/bin/env python3
"""Builds the site into dist/site/: one page per translation bundle.

    python3 scripts/build.py [--stage prod|rc|local] [--origin URL] [--version X.Y.Z] [--commit SHA]

- site/index.html is a template; each {{key}} is replaced by that key's text
  from a bundle in site/i18n/<lang>.json. English (en.json) is the default
  and goes to /index.html; every other language goes to /<lang>/index.html.
  {{lang}}, {{locale}}, {{home}}, {{canonical}}, {{alternates}} and
  {{languages}} are filled in by this script.
- Every bundle must have exactly the keys en.json has, and every {{key}} in
  the template must resolve, or the build fails.
- The rest of site/ (CSS, JS, images) is copied as is, minus the template
  and the bundles.
- version.json reports the version, commit and stage; the deploy checks it.
- With --stage rc, site_rc/ is copied over the result (its own favicon),
  titles get a "🧪 RC" prefix, and robots.txt keeps crawlers out.
- --stage local is the dev server's build (scripts/dev.py): site_local/
  over the result, a "🛠 LOCAL" prefix and badge, crawlers kept out, and
  URLs on --origin (default http://localhost:8090).

Bundle values are trusted HTML (they live in this repository): they may
hold inline markup such as <strong> or <a>.
"""
import argparse
import html
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
I18N = SITE / "i18n"
DEFAULT_LANG = "en"
ORIGINS = {"prod": "https://nu01.com", "rc": "https://rc.nu01.com", "local": "http://localhost:8090"}
PREFIXES = {"rc": "🧪 RC · ", "local": "🛠 LOCAL · "}
PLACEHOLDER = re.compile(r"\{\{([a-zA-Z0-9_.]+)\}\}")


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def load_bundles():
    bundles = {}
    for path in sorted(I18N.glob("*.json")):
        with path.open(encoding="utf-8") as f:
            bundle = json.load(f)
        if bundle.get("lang") != path.stem:
            fail(f"{path.name}: \"lang\" must be \"{path.stem}\"")
        bundles[path.stem] = bundle
    if DEFAULT_LANG not in bundles:
        fail(f"site/i18n/{DEFAULT_LANG}.json is missing")
    keys = set(bundles[DEFAULT_LANG])
    for lang, bundle in bundles.items():
        missing, extra = keys - set(bundle), set(bundle) - keys
        if missing or extra:
            fail(f"{lang}.json: missing {sorted(missing)}, extra {sorted(extra)}")
        empty = [k for k, v in bundle.items() if not str(v).strip()]
        if empty:
            fail(f"{lang}.json: empty {empty}")
    # English first, then the others alphabetically.
    order = [DEFAULT_LANG] + sorted(l for l in bundles if l != DEFAULT_LANG)
    return {lang: bundles[lang] for lang in order}


def path_for(lang):
    return "/" if lang == DEFAULT_LANG else f"/{lang}/"


def render(template, bundle, bundles, origin, stage):
    lang = bundle["lang"]
    values = dict(bundle)
    values["meta.title"] = PREFIXES.get(stage, "") + values["meta.title"]
    values["stage"] = stage
    values["home"] = path_for(lang)
    values["canonical"] = origin + path_for(lang)
    values["alternates"] = "\n".join(
        [f'  <link rel="alternate" hreflang="{l}" href="{origin}{path_for(l)}">' for l in bundles]
        + [f'  <link rel="alternate" hreflang="x-default" href="{origin}/">']
    )
    values["languages"] = "\n".join(
        f'        <li><a href="{path_for(l)}" hreflang="{l}" lang="{l}" data-lang="{l}"'
        + (' aria-current="page"' if l == lang else "")
        + f'>{html.escape(b["name"])}</a></li>'
        for l, b in bundles.items()
    )

    def replace(match):
        key = match.group(1)
        if key not in values:
            fail(f"site/index.html: {{{{{key}}}}} isn't in {lang}.json")
        value = values[key]
        # meta.* go into attributes and <title>: plain text, escaped.
        if key.startswith("meta.") or key in ("hero.pause", "hero.play", "hero.label", "hero.choose", "nav.home", "nav.language"):
            return html.escape(value, quote=True)
        return value

    return PLACEHOLDER.sub(replace, template)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=sorted(ORIGINS), default="prod")
    parser.add_argument("--version", default="0.0.0")
    parser.add_argument("--commit", default="unknown")
    parser.add_argument("--origin", help="the site's own URL (default: the stage's)")
    parser.add_argument("--out", default=str(ROOT / "dist" / "site"))
    args = parser.parse_args()

    out = Path(args.out)
    origin = (args.origin or ORIGINS[args.stage]).rstrip("/")
    bundles = load_bundles()
    template = (SITE / "index.html").read_text(encoding="utf-8")

    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(SITE, out, ignore=shutil.ignore_patterns("i18n", "index.html", ".DS_Store"))
    if args.stage != "prod":
        shutil.copytree(ROOT / f"site_{args.stage}", out, dirs_exist_ok=True)

    for lang, bundle in bundles.items():
        target = out / path_for(lang).lstrip("/") / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render(template, bundle, bundles, origin, args.stage), encoding="utf-8")

    (out / "version.json").write_text(
        json.dumps({"version": args.version, "commit": args.commit, "stage": args.stage}) + "\n",
        encoding="utf-8",
    )
    if args.stage != "prod":
        robots = "User-agent: *\nDisallow: /\n"
    else:
        robots = f"User-agent: *\nAllow: /\n\nSitemap: {origin}/sitemap.xml\n"
    (out / "robots.txt").write_text(robots, encoding="utf-8")
    urls = "\n".join(f"  <url><loc>{origin}{path_for(l)}</loc></url>" for l in bundles)
    (out / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f"{urls}\n</urlset>\n",
        encoding="utf-8",
    )
    print(f"built {args.stage} {args.version} ({', '.join(bundles)}) into {out}")


if __name__ == "__main__":
    main()
