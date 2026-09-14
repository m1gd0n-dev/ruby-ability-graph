# Contributing

## Setup

```
bin/setup            # bundle install
bundle exec rspec
bundle exec rubocop
```

PRs must pass both before merge (see `.github/workflows/ci.yml`).

## What's welcome

- Bug fixes.
- Additional CanCanCan pattern coverage within the existing `resolved`/`unsupported`
  model (e.g. a hash-condition shape that should resolve but doesn't).
- Fixture coverage against real-world `Ability` classes.
- Docs.

## What's not

PRs implementing resolution for block conditions, association-chained conditions,
or dynamic/computed rule generation won't be merged -- these are deliberately kept
`unsupported` rather than guessed at. See the README's "Status" section for the
resolved/unsupported boundary this project maintains.

## Response time

Solo-maintained. No SLA -- I'll get to issues and PRs when I can.
