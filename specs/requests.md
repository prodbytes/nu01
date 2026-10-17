# Request log

Requests that shaped the specification, oldest first. Each entry summarizes
what was asked and what changed. See [README.md](README.md) for the current
spec.

## 2026-10-08

1. **Create the nu01.com website repository.** A static site for the root
   domain: title "nu01.com is LEARNWARE", a description (learnable systems,
   video explanations at prodbytes.substack.com, freemium with premium for
   prodbytes members) and a hero rotating between "More than AI: people
   learning", presence, uplink and rbacr, with reviewed texts and
   generated images. RC/GA releases like prodbytes/presence, aimed at
   nu01.com (RC at rc.nu01.com); the current static site (a redirect to
   prodbytes.substack.com) is to be deleted and replaced. CLAUDE.md and
   AGENTS.md rules copied from presence and adapted.
2. **Internationalize it.** Bundles in English (default), Spanish,
   Portuguese and Catalan; one page per language.
3. **Test on RC before GA.** `release-ga.sh` refuses a commit that hasn't
   been live on rc.nu01.com; the user checks the RC first.
4. **Use the HTML5 UP Dimension template.** The page is now Dimension, with
   the heroes as its articles and a rotating hero line and background.

## 2026-10-10

1. **Move everything into the GitHub repository and add a dev server.**
   The site went onto a branch of `prodbytes/nu01` (created with a README
   on `main`). `devbox services up` now starts a dev server
   (process-compose: `scripts/dev.py` on http://localhost:8090/, rebuilt on
   every change, pages marked LOCAL) and a health monitor. The build gained
   a `local` stage.
2. **Run the local server on port 1415.** The dev server, the health
   monitor and the `local` build stage's origin moved from port 8090 to
   http://localhost:1415/ (still overridable with `NU01_PORT`).
3. **Set up local records on Route 53 so local HTTPS works.** Created the
   A record `local.nu01.com` → `127.0.0.1` in the `nu01.com` zone.
   `scripts/local-certs.sh` makes an mkcert certificate (devbox gained
   mkcert and openssl), and the dev server also serves
   https://local.nu01.com:1443/; the health monitor checks it.
4. **One health-check line per run, and the URLs once.** Every check on
   the line has an icon, a short label and ✅/❌ (each language page now
   has its own 🌐); the local URLs are printed once when the monitor
   starts, not on every run.
5. **Open external links in a new tab, and make it a rule.** Every link to
   another host, nu01.com subdomains included, now has `target="_blank"
   rel="noopener"` (template and bundles); the build fails on one without
   them, and CLAUDE.md states the rule.
6. **Add tabscan to the apps list, with its hero and all.** tabscan
   (scan guitar tabs with the phone, read them as text, share them) is the
   fifth hero: a nav button, a rotating hero line, an article with an
   illustration (`site/img/tabscan.svg`) linking to
   https://tabscan.nu01.com/app/, and a generated background
   (`site/images/bg-tabscan.jpg`), in all four languages.
7. **Link each project's GitHub repository.** The presence, uplink, rbacr
   and tabscan articles have a "Source on GitHub" button (in every
   language) to `github.com/prodbytes/<app>`, opening in a new tab.
8. **Fix the zone lookup in bootstrap, deploy and retire-legacy.** The
   AWS CLI (2.37) never matches `!Config.PrivateZone` in a query, so the
   scripts found no `nu01.com` zone and the deploy-roles stack failed
   (`HostedZoneId` None). They now test ``Config.PrivateZone==`false` ``.
9. **Say "free access" and "premium access" instead of "freemium".** The
   intro line and the meta description, in all four languages, now say
   every service offers free access to everyone, and premium access is
   included for all prodbytes members (first drafted with "role", which
   the user dropped for "access").
10. **Add a prodbytes link to the nav bar.** After the five heroes, the nav
    bar links to https://prodbytes.substack.com/ in a new tab. The hero
    script now only treats nav links with a hero as heroes. Six buttons
    overflowed narrower screens, so the bar tightens below 900px and
    stacks up to 640px.
11. **Make it clear you can sign up, get access to all the apps and support
    us.** Under the access line, a sentence says so and a "Sign up on
    Substack" button links to https://prodbytes.substack.com/subscribe, in
    all four languages.

## 2026-10-13

1. **Feature grigri, and publish it all.** grigri (matchmaking for climbing:
   swipe on plans, match when the whole group says yes, climb together) is
   the sixth hero: a nav button, a rotating hero line, an article with an
   illustration (`site/img/grigri.svg`), an "Open grigri" button to
   https://grigri.nu01.com/ and a "Source on GitHub" button to
   `prodbytes/grigri`, and a generated background
   (`site/images/bg-grigri.jpg`), in all four languages. With seven nav
   buttons, the tighter bar now starts below 1000px (was 900px). Published with the
   sign-up call (PR #11) through RC to GA.

## 2026-10-14

1. **Cut AWS cost.** Every stack is tagged `project=nu01` and `tenancy=GA`,
   `RC` or `shared` for cost allocation. The apps' 14 Route 53 health
   checks (about $24/month) are replaced by the `nu01-monitor` stack: a
   Lambda function checking the same endpoints every 5 minutes, with one
   alarm emailing `julio+health@nu01.com` ([monitor.md](monitor.md)).
2. **Keep the shared infrastructure here, and merge the app subzones.** The
   `nu01-route53-zone` and `nu01-route53-gmail` stacks moved from
   prodbytes/dsp (templates unchanged, now tagged); a new `nu01-dns` stack
   and `scripts/migrate-subzone.sh` merge grigri., tabscan., rbacr. and
   uplink.nu01.com ($0.50/month each) into the nu01.com zone one project at
   a time, keeping each subzone for 48 hours after its delegation is
   removed ([dns.md](dns.md)).

## 2026-10-17

1. **Links to open all apps.** uplink was the only app whose article had
   no link to open it; it now has an "Open uplink" button to
   https://uplink.nu01.com/ (above the source button, under the install
   one-liner), in all four languages. Every app now opens from its article.
