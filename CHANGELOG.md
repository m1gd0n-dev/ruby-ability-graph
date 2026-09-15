# Changelog

All notable changes to this project are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.2] - 2026-09-15

### Fixed
- `--html-report`: aggregated role→action and action→model edges no longer
  paint the whole bundle amber over a single unsupported row. Edge color now
  reflects the fraction of the bundle that's resolved.

### Changed
- Gemspec: tighten description wording.

## [0.1.1] - 2026-09-15

### Changed
- README: add a screenshot of the `--html-report` graph.
- Gemspec: tighten summary/description wording.

## [0.1.0] - 2026-09-14

Initial release.

### Added
- `scan`: loads a Rails app's CanCanCan `Ability` class and reports `can?`/`cannot?`
  results across every role x action x model combination.
- Condition classification: flat scalar hash conditions resolve to structured
  output; blocks, association-chained, and other opaque conditions are tagged
  `unsupported` rather than guessed at.
- `--format table|json` output, including a versioned JSON schema.
- `--policy-file`: diff results against a declared role/action/model policy,
  flagging both violations and unmatched policy entries; exits non-zero on either.
- `--html-report`: self-contained, offline HTML graph of the results.
- `inspect`: static scan (via Prism) listing methods a target's `Ability#initialize`
  calls on `user`, to help write a roles file.
- `--ability-class`, `--require`, `--rails-boot`, `--ruby-bin` flags for loading
  Ability classes across namespaces, dependencies, and Ruby versions.
- CanCanCan 1.x and 3.x compatibility.
