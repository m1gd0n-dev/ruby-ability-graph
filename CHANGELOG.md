# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project has not yet reached v1; until then, expect breaking changes
between minor versions.

## [Unreleased]

Condition structuring and `resolved`/`unsupported` classification -- the
core v1 differentiator -- is not yet implemented. Everything below is raw
`can?`/`cannot?` capture.

### Changed

- **License changed from MIT to AGPL-3.0-or-later.** 0.1.0 was released
  under MIT; going forward, forking or hosting this as a service requires
  releasing your modifications under the same license -- see
  [`LICENSE.txt`](./LICENSE.txt).

## [0.1.0] - 2026-09-02

Initial pre-release. Not yet published to RubyGems.

### Added

- `scan APP_PATH`: loads a target app's CanCanCan `Ability` class in
  isolation and reports raw `can?`/`cannot?` results across the
  role x action x model cross-product, defined via a `.ability_graph_roles.yml`
  (or `--roles-file`) role stand-in file.
- `inspect APP_PATH`: static source scan (via [Prism](https://github.com/ruby/prism),
  never executes the target) listing every method called on `user` in
  `Ability#initialize` -- a roles-file authoring aid (#1).
- `--require FILE` (repeatable): manual preload for models an `Ability`
  class references but doesn't `require` itself -- a Zeitwerk-autoloading
  workaround for small apps/quick scans (#2).
- `--rails-boot` (`[--rails-env ENV]`): runs the scan inside the target's
  own `bin/rails runner`, so real Zeitwerk autoloading resolves every
  referenced class with no manual `--require` list (#3).
- Docker quickstart (`docker build` / `docker compose run`), including
  guidance to mount scan targets read-only (`:ro`).
- Security documentation of the scan-executes-target-code trust model
  (see the README's Security section and [`security_report/`](./security_report/)).
- CI: rspec + rubocop on every PR and push to `main`.

[Unreleased]: https://github.com/m1gd0n-dev/ruby-ability-graph/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/m1gd0n-dev/ruby-ability-graph/releases/tag/v0.1.0
