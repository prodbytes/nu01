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
