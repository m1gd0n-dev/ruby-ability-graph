# Contributing

## Setup

```
bin/setup            # bundle install
bundle exec rspec
bundle exec rubocop
```

Please make sure both checks pass before opening a PR. The CI workflow lives in `.github/workflows/ci.yml`.

## Contributions welcome

- Bug fixes.
- More CanCanCan pattern coverage within the existing `resolved`/`unsupported`
  model. For example, a hash condition that should resolve but currently does not.
- Fixtures based on real-world `Ability` classes.
- Documentation improvements.

## Out of scope

This project intentionally does not try to resolve block conditions,
association-chained conditions, or dynamically generated rules. The scanner marks
them as `unsupported`, so PRs that add resolution for them are out of scope. The
README's "Status" section explains where that boundary is.

## Response time

This is a solo-maintained project. There is no response-time guarantee, but I will
get to issues and PRs when I can.
