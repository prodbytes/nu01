# shellcheck shell=bash disable=SC2034
# Sourced by the build, deploy and release scripts. Sets the site version,
# X.Y.Z:
#   VERSION_X, VERSION_Y  from version.X.txt and version.Y.txt at the repo root
#   VERSION_Z             the build time as a UTC timestamp, YYYYMMDDHHMM,
#                         unless VERSION_Z is already set
#   VERSION               "$VERSION_X.$VERSION_Y.$VERSION_Z"
# Returns non-zero if a version file or a preset value isn't a plain number.

_whole() {
  local name
  for name in "$@"; do
    if [[ ! "${!name}" =~ ^(0|[1-9][0-9]*)$ ]]; then
      echo "error: $name must be a whole number (got '${!name}')" >&2
      return 1
    fi
  done
}

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_X="$(tr -d '[:space:]' < "$_root/version.X.txt")"
VERSION_Y="$(tr -d '[:space:]' < "$_root/version.Y.txt")"
unset _root
_whole VERSION_X VERSION_Y || { unset -f _whole; return 1; }
VERSION_Z="${VERSION_Z:-$(date -u +%Y%m%d%H%M)}"
_whole VERSION_Z || { unset -f _whole; return 1; }
unset -f _whole
VERSION="$VERSION_X.$VERSION_Y.$VERSION_Z"
