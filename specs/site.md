# Site

## Content

- **Title:** "nu01.com is LEARNWARE" (LEARNWARE in the accent green).
- **Description:** more than apps, AI and open source, nu01 systems are
  learnable, with full video explanations at prodbytes.substack.com.
- **Access line:** every service offers free access to everyone, and
  premium access is included for all prodbytes members (neither
  "freemium" nor "role" is used).
- **Heroes**, rotating every 7 seconds under the description, each opening
  an article with an illustration, a paragraph and a link; each app's
  article also has a "Source on GitHub" button to its repository:

  | Hero | Headline (English) | Link | Repository |
  |---|---|---|---|
  | Learnware | More than AI: people learning | https://prodbytes.substack.com/ | — |
  | presence | Keep an eye on the places you care for | https://presence.nu01.com/ | https://github.com/prodbytes/presence |
  | uplink | Find every broken link | the install one-liner, `curl -fsSL https://sh.uplink.nu01.com \| sh -s -- https://nu01.com` | https://github.com/prodbytes/uplink |
  | rbacr | Roles for every app you run | https://rbacr.nu01.com/ | https://github.com/prodbytes/rbacr |
  | tabscan | Scan and share guitar tabs | https://tabscan.nu01.com/app/ | https://github.com/prodbytes/tabscan |

## Behaviour

- The hero line, the page background (one image per hero) and the
  highlighted nav button change together.
- Rotation waits while an article is open or the header is hovered or
  focused; the pause button stops and restarts it; it doesn't run at all
  with `prefers-reduced-motion`.
- The nav buttons and the hero line open the articles (Dimension's
  `#learning`, `#presence`, `#uplink`, `#rbacr`, `#tabscan`); a link with one of those
  hashes opens straight on it.
- Links to other hosts (other domains and nu01.com subdomains, e.g. the
  article buttons, prodbytes.substack.com, HTML5 UP) open in a new tab
  (`target="_blank" rel="noopener"`); links within the site don't.
  `scripts/build.py` fails the build on an external link without both.
- The footer lists the languages, credits HTML5 UP, and shows the deployed
  version from `/version.json`.
- On rc.nu01.com every page has an "RC" badge, a red "RC" favicon, titles
  prefixed "🧪 RC ·", and `robots.txt` disallows crawling.

## Template and images

- [Dimension](https://html5up.net/dimension) by HTML5 UP, CC BY 3.0 (its
  license in `site/assets/LICENSE-html5up.txt`, credit in the footer). Its
  CSS and JS are unchanged; nu01's changes are `site/assets/css/nu01.css`
  and `site/assets/js/nu01.js`. Its demo pictures aren't used.
- `site/img/*.svg`: one illustration per article, drawn for this site (no
  words in them, so they suit every language). Placeholders until real
  screenshots or artwork replace them.
- `site/images/bg-<hero>.jpg`: generated abstract backgrounds, one per hero.
