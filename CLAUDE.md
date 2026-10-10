@AGENTS.md

## Keep the specification up to date

After every user request, update the [specs/](specs/) folder in the same
change:

- Add a dated entry to [specs/requests.md](specs/requests.md) that says what
  was asked and what changed.
- Revise the feature specs the request touches, one file per feature (the
  index is [specs/README.md](specs/README.md)), so they describe the
  site as it is now. Add a feature file, and list it in the index, when a
  request adds a feature. Rewrite or delete statements the request made
  obsolete; don't just append.

## One pull request per change

Every new feature or bug fix starts on a **new branch from `main`**, with its
own pull request:

- Never commit or push directly to `main`.
- Don't bundle unrelated requests into one PR.
- Start from an up-to-date `main` (`git checkout main && git pull`). Stack on
  an unmerged branch only when the new work truly depends on it, and then
  target that branch.
- Merge only when the user says so.
- Include the matching `specs/` update in the same PR as the change.

## Every text in every language

The site's words live in the bundles in [site/i18n/](site/i18n/): English
(`en.json`, the default) plus Spanish, Portuguese and Catalan. A change to
any text changes it in **all** bundles in the same PR; the build fails when
their keys differ. Never put words in [site/index.html](site/index.html)
itself.

## External links open in a new tab

A link to any other host (another domain, or even a nu01.com subdomain
such as presence.nu01.com) opens in a new tab: `target="_blank"
rel="noopener"`, in [site/index.html](site/index.html) and in the bundles
alike. Links within the site (the language links, `#article` hashes) stay
in the same tab. The build fails on an external link without both.

## RC before GA

A release is tested on **https://rc.nu01.com** before it reaches
https://nu01.com. Cut the RC (`bash scripts/release-rc.sh`), wait for Deploy
RC, and let the user check it. Cut GA (`bash scripts/release-ga.sh`) only
when the user says so; the script refuses a commit without an RC tag, or
one rc.nu01.com doesn't serve.

## Do a barrel roll

"Do a barrel roll" (also written "barrell roll") means: run a complete
cycle, in this order, stopping to report if any step fails:

1. **Commit** the pending changes (each on its own branch and PR, as above,
   with their `specs/` updates).
2. **Build** the site and **check it** (`STAGE=rc bash scripts/build.sh` and
   `STAGE=prod bash scripts/build.sh`), then **deploy locally**: start the
   dev server (`devbox services up`), check every health line is ✅, and
   look at every language.
3. **Merge** the open PRs into `main`.
4. **Cut the RC**: an annotated tag on the merge commit at the tip of
   `main` (see [specs/release.md](specs/release.md)), pushed so the Release
   and Deploy RC workflows run.
5. **Check the RC live**: wait for Deploy RC to finish, then confirm
   https://rc.nu01.com/version.json reports the new tag's version and
   commit. Report it, and wait for the user to check the RC.
6. **Cut GA** only when the user approves the RC, then confirm
   https://nu01.com/version.json reports the GA's version.
