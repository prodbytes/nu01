#!/usr/bin/env bash
# Builds the site into dist/site/ (see scripts/build.py).
#   STAGE   prod (default) or rc
#   TAG     a release tag, X.Y.Z-KK: its Z becomes the version's Z, and its
#           X.Y must match the version files (default: none, Z = now)
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="${STAGE:-prod}"
if [[ "${TAG:-}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)?$ ]]; then
  export VERSION_Z="${BASH_REMATCH[3]}"
  tag_xy="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
elif [[ -n "${TAG:-}" ]]; then
  echo "error: TAG '$TAG' isn't X.Y.Z[-suffix]" >&2
  exit 2
fi
source scripts/version.sh
if [[ -n "${tag_xy:-}" && "$tag_xy" != "$VERSION_X.$VERSION_Y" ]]; then
  echo "error: tag $TAG is version $tag_xy, but version.X.txt/version.Y.txt say $VERSION_X.$VERSION_Y" >&2
  exit 1
fi
commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
python3 scripts/build.py --stage "$STAGE" --version "$VERSION" --commit "$commit"
