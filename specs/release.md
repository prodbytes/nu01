# Release

## Versions

`X.Y.Z`, from [scripts/version.sh](../scripts/version.sh): X and Y from
`version.X.txt` and `version.Y.txt` (now `0` and `1`), Z the UTC time,
`YYYYMMDDHHMM`. A tag carrying `X.Y.Z` keeps its Z, and its X.Y must match
the files. The build writes `version.json`: version, commit and stage.

## Tags

- `bash scripts/release-rc.sh` tags `X.Y.Z-RC` and pushes it: Deploy RC
  publishes it to https://rc.nu01.com, and Release makes a prerelease
  `nu01-X.Y.Z-RC` with the built site as `nu01-<tag>-site.zip`.
- `bash scripts/release-ga.sh` tags `X.Y.Z-GA` and pushes it: Deploy
  publishes it to https://nu01.com, and Release makes the latest release.
- Both run [scripts/tag-release.sh](../scripts/tag-release.sh), which
  refuses uncommitted changes, unpushed commits and existing tags.
  `DRY_RUN=1` only prints the tag.

## RC before GA

GA is refused unless the commit is on `main`, carries an `*-RC*` tag, and
https://rc.nu01.com/version.json reports that commit: a GA is always a
commit that has been live on RC. The user checks the RC before GA is cut.

## Pull requests

The Release workflow builds both stages on every pull request and fails if
a page has an unresolved placeholder.
