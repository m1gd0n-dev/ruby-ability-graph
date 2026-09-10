# ruby_ability_graph

Loads a Rails app's [CanCanCan](https://github.com/CanCanCommunity/cancancan) `Ability` class in isolation and reports raw `can?`/`cannot?` results across every role x action x model combination -- so you can see who can access what without booting the full app or hand-tracing every conditional.

**Status:** Each result is now classified `resolved` (structured condition captured) or `unsupported` (declared but not analyzed, with a reason and source pointer) per the v1 scope contract. Table/HTML output and a policy-check mode are still planned.

## Installation

Not on RubyGems yet -- point Bundler at the repo instead:

```ruby
gem "ruby_ability_graph", github: "m1gd0n-dev/ruby-ability-graph"
```

Requires Ruby >= 4.0.

## Usage

### 1. Find out what your Ability class needs

`inspect` statically scans `Ability#initialize` (via [Prism](https://github.com/ruby/prism), without executing your app) and lists every method it calls on `user`:

```
ruby-ability-graph inspect APP_PATH [--ability-file FILE]
```

```
Methods called on `user` in Ability#initialize:
  admin?
  id

Your roles file needs a value for each, per role that reaches it.
```

### 2. Write a roles file

Create `.ability_graph_roles.yml` at your app root, mapping each role you want scanned to stand-in values for the methods `inspect` found:

```yaml
admin:
  admin?: true
member:
  admin?: false
  id: 42
```

### 3. Scan

```
ruby-ability-graph scan APP_PATH [--roles-file FILE] [--ability-file FILE]
                                  [--require FILE]... | [--rails-boot [--rails-env ENV]]
                                  [--ruby-bin PATH]
```

This loads your `Ability` class in a subprocess, runs `can?` for every role x action x model combination it finds, and prints the results as JSON:

```json
{
  "raw_results": [
    { "role": "admin", "action": "read", "model": "Document", "allowed": true,
      "confidence": "resolved", "condition": null, "reasons": [], "sources": [] },
    { "role": "member", "action": "read", "model": "Document", "allowed": true,
      "confidence": "resolved", "condition": { "team_id": 7 }, "reasons": [], "sources": [] },
    { "role": "member", "action": "update", "model": "Document", "allowed": true,
      "confidence": "unsupported", "condition": null, "reasons": ["block_condition"],
      "sources": [{ "file": "app/models/ability.rb", "line": 12, "text": "can :update, Document do |doc| ... end" }] }
  ]
}
```

**Options:**

| Flag | Default | Purpose |
|---|---|---|
| `--roles-file FILE` | `APP_PATH/.ability_graph_roles.yml` | YAML file from step 2 |
| `--ability-file FILE` | `app/models/ability.rb` | Path to the `Ability` class, relative to `APP_PATH` |
| `--require FILE` (repeatable) | -- | Preload a file your `Ability` class references but doesn't require itself. Not compatible with `--rails-boot` |
| `--rails-boot [--rails-env ENV]` | off / `test` | Boot via the target's own `bin/rails runner` so real Zeitwerk autoloading resolves everything -- no manual `--require` list needed. Not compatible with `--require` |
| `--ruby-bin PATH` | `ruby` (via `PATH`) | Ruby executable for the analysis subprocess, if the target app needs a different Ruby version than this gem runs under |

## Security

`scan` executes code in `APP_PATH` -- it loads your `Ability` class (and anything that file requires) in a subprocess. Only run it against apps you trust. `inspect` is static analysis only (via Prism) and never executes the target.
