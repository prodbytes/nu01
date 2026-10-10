#!/usr/bin/env bash
# Tags the current commit with the current version and a release kind, and
# pushes the tag, which starts the deploy and release workflows. Used by
# scripts/release-rc.sh and scripts/release-ga.sh: `bash scripts/tag-release.sh RC|GA`.
#
# The tag is X.Y.Z-<kind>: X and Y from version.X.txt and version.Y.txt, Z
# the current time (see scripts/version.sh). DRY_RUN=1 checks and prints the
# tag without creating it.
#
# A GA must be tested on RC first: the commit must be on main, carry an RC
# tag, and be what https://rc.nu01.com serves (its version.json commit).
set -euo pipefail

kind="${1:-}"
case "$kind" in
  RC | GA) ;;
  *) echo "usage: $0 RC|GA" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
source scripts/version.sh
tag="$VERSION-$kind"
head="$(git rev-parse HEAD)"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "error: uncommitted changes; commit and push them first" >&2
  exit 1
fi
git fetch --quiet --tags origin
if [[ -z "$(git branch --remotes --contains HEAD)" ]]; then
  echo "error: $(git rev-parse --short HEAD) isn't pushed; push it first" >&2
  exit 1
fi
if [[ "$kind" == GA ]]; then
  if ! git merge-base --is-ancestor HEAD origin/main; then
    echo "error: a GA release must be a commit on main (check out main and pull)" >&2
    exit 1
  fi
  if [[ -z "$(git tag --points-at HEAD --list '*-RC*')" ]]; then
    echo "error: $(git rev-parse --short HEAD) has no RC tag; release and test an RC first (scripts/release-rc.sh)" >&2
    exit 1
  fi
  rc_commit="$(curl -fsS --max-time 20 "https://rc.nu01.com/version.json?ga=$VERSION_Z" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["commit"])' || true)"
  if [[ "$rc_commit" != "$head" ]]; then
    echo "error: https://rc.nu01.com serves ${rc_commit:-nothing readable}, not $head; wait for Deploy RC and test it first" >&2
    exit 1
  fi
fi
if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null ||
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null; then
  echo "error: tag $tag already exists; try again in a minute" >&2
  exit 1
fi

echo "Tagging $(git rev-parse --short HEAD) as $tag"
if [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Dry run: not tagged."
  exit 0
fi
git tag --annotate "$tag" --message "nu01 $tag"
git push --quiet origin "refs/tags/$tag"
url="$(git remote get-url origin | sed -e 's#^git@github.com:#https://github.com/#' -e 's#\.git$##')"
if [[ "$kind" == RC ]]; then
  echo "Pushed $tag. Deploy RC publishes it to https://rc.nu01.com: $url/actions/workflows/deploy-rc.yml"
else
  echo "Pushed $tag. Deploy publishes it to https://nu01.com: $url/actions/workflows/deploy.yml"
fi
