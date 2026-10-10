# nu01.com

**nu01.com is LEARNWARE.** More than apps, AI and open source: nu01 systems
are learnable, with full video explanations at
[prodbytes.substack.com](https://prodbytes.substack.com/). Every service
offers free access to everyone, and premium access is included for all
prodbytes members.

This repository is the website at https://nu01.com: one static page that
rotates through five heroes (Learnware, [presence](https://presence.nu01.com),
uplink, [rbacr](https://rbacr.nu01.com) and
[tabscan](https://tabscan.nu01.com/app/)), in English (default), Spanish,
Portuguese and Catalan.

- Production: **https://nu01.com** (`*GA` tags)
- Release candidate: **https://rc.nu01.com** (`*RC*` tags)

## Working on it

```sh
devbox services up           # dev server on http://localhost:1415/ + health monitor
```

The dev server ([process-compose.yaml](process-compose.yaml),
[scripts/dev.py](scripts/dev.py)) builds the site marked LOCAL, serves it
like CloudFront does, and rebuilds within a second of any change under
`site/`. A broken build is printed and the last good one keeps being
served. Without devbox: `bash scripts/serve.sh`. Port: `NU01_PORT`.

- Words: [site/i18n/](site/i18n/) (`en.json`, `es.json`, `pt.json`,
  `ca.json`). Every bundle has the same keys; change all four together.
- Layout: [site/index.html](site/index.html), a template filled per language
  by [scripts/build.py](scripts/build.py). English goes to `/`, the others to
  `/es/`, `/pt/` and `/ca/`.
- Look: [Dimension](https://html5up.net/dimension) by HTML5 UP (CC BY 3.0,
  credited in the footer), with nu01's changes in
  [site/assets/css/nu01.css](site/assets/css/nu01.css) and
  [site/assets/js/nu01.js](site/assets/js/nu01.js).
- Images: [site/img/](site/img/) (the article illustrations, SVG) and
  [site/images/](site/images/) (one background per hero).

## Releasing: RC, then GA

```sh
bash scripts/release-rc.sh   # tag X.Y.Z-RC → Deploy RC → https://rc.nu01.com
# check https://rc.nu01.com/ in every language
bash scripts/release-ga.sh   # tag X.Y.Z-GA → Deploy → https://nu01.com
```

`release-ga.sh` refuses unless the commit is on `main`, has an RC tag, and
is what https://rc.nu01.com serves. Details: [specs/release.md](specs/release.md)
and [specs/deploy.md](specs/deploy.md).

## First-time setup

1. `bash scripts/bootstrap.sh` (gh signed in, admin AWS credentials):
   creates `prodbytes/nu01`, pushes `main`, deploys the deploy roles, sets
   the repository variables and cuts the first RC.
2. Check https://rc.nu01.com/.
3. `bash scripts/retire-legacy.sh` shows what serves nu01.com today (the
   CloudFront + S3 redirect to prodbytes.substack.com);
   `CONFIRM=yes bash scripts/retire-legacy.sh` backs up and deletes it.
4. `bash scripts/release-ga.sh` right away, since nu01.com is down between
   steps 3 and 4.
