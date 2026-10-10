# nu01.com — specification

The current specification of the site, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that
shaped it.

## Product

https://nu01.com is one static page that says what nu01 is
(**LEARNWARE**: learnable systems, explained on video at
prodbytes.substack.com, a free role for everyone and a premium role for
prodbytes members) and
rotates through nu01's systems.

## Features

- [Site](site.md): the page, its heroes and articles, the template and images.
- [Languages](i18n.md): the bundles, the pages per language, and how a
  language is picked.
- [Dev environment](dev-environment.md): devbox, the dev server and its
  health monitor.
- [Release](release.md): versions, RC and GA tags, and the rule that GA
  follows a checked RC.
- [Deploy](deploy.md): the AWS stacks, the workflows and their roles, the
  smoke test, and retiring the old nu01.com site.
