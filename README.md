# ruby_ability_graph

Loads a Rails app's [CanCanCan](https://github.com/CanCanCommunity/cancancan) `Ability` class in isolation and reports raw `can?`/`cannot?` results across every role x action x model combination -- so you can see who can access what without booting the full app or hand-tracing every conditional.

**Status:** Each result is classified `resolved` (structured condition captured) or `unsupported` (declared but not analyzed, with a reason and source pointer). `scan` prints a human-readable table by default, a versioned JSON schema on request, can diff results against a simple policy file, and can render an interactive HTML graph of the whole thing.

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
ruby-ability-graph inspect APP_PATH [--ability-file FILE] [--ability-class NAME]
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
ruby-ability-graph scan APP_PATH [--roles-file FILE] [--ability-file FILE] [--ability-class NAME]
                                  [--require FILE]... | [--rails-boot [--rails-env ENV]]
                                  [--ruby-bin PATH] [--format table|json] [--policy-file FILE]
                                  [--html-report FILE]
```

This loads your `Ability` class in a subprocess and runs `can?` for every role x action x model combination it finds.

By default it prints a human-readable table plus a resolved/unsupported coverage line:

```
ROLE    ACTION  MODEL     ALLOWED  CONFIDENCE   CONDITION
admin   read    Document  true     resolved     -
member  read    Document  true     resolved     {"team_id" => 7}
member  update  Document  true     unsupported  -

2/3 resolved (66.7%)
```

Pass `--format json` for the same data as structured, versioned JSON instead:

```json
{
  "schema_version": 1,
  "results": [
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
| `--ability-class NAME` | `Ability` | Constant name to load, e.g. `Spree::Ability` for a namespaced/engine-provided one |
| `--require FILE` (repeatable) | -- | Preload a file your `Ability` class references but doesn't require itself. Not compatible with `--rails-boot` |
| `--rails-boot [--rails-env ENV]` | off / `test` | Boot via the target's own `bin/rails runner` so real Zeitwerk autoloading resolves everything -- no manual `--require` list needed. Not compatible with `--require` |
| `--ruby-bin PATH` | `ruby` (via `PATH`) | Ruby executable for the analysis subprocess, if the target app needs a different Ruby version than this gem runs under |
| `--format table\|json` | `table` | `table` for a terminal-friendly summary, `json` for the versioned schema above |
| `--policy-file FILE` | -- | Run a policy check against the results (see below); path is relative to `APP_PATH` |
| `--html-report FILE` | -- | Write an interactive HTML graph of the results (see below) to this path, relative to `APP_PATH` |

Note: `--rails-boot` runs the target's *entire* boot sequence, not just the `Ability` class -- if the app needs a JS runtime, a live DB connection, or anything else at boot time (not merely at asset-compile time), that has to already be satisfied in whatever environment you're running the scan from. This is most likely to bite in a stripped-down CI container or sandbox rather than a normal dev machine. If the target's full boot is heavy or fragile, `--require`ing just what the `Ability` class needs is usually simpler than fighting its boot process.

### 4. Policy checks (optional)

Declare who's *supposed* to be able to do what, and let `scan` flag any role that can actually do more. The policy language is deliberately flat -- `model` + `action` + `allowed_roles`, no nested logic:

```yaml
# policy.yml
policies:
  - model: Payment
    action: read
    allowed_roles: [admin]
  - model: Document
    action: destroy
    allowed_roles: [admin, owner]
```

```
ruby-ability-graph scan APP_PATH --policy-file policy.yml
```

A violation is any `(role, action, model)` combination the scan found `allowed: true` for, where `role` isn't in that policy's `allowed_roles`. Violations are appended to the table (or the `"policy_violations"` key in JSON output), and `scan` exits `1` if any are found -- so this doubles as a CI gate. A clean policy check exits `0`.

Note: a policy check is only as trustworthy as the underlying result's `confidence`. A violation on an `unsupported` result means the role stand-in used for this run happened to be allowed -- it isn't a guarantee about every user with that role, since the condition itself wasn't fully analyzed. Treat those as "investigate," not "confirmed."

### 5. HTML report (optional)

```
ruby-ability-graph scan APP_PATH --html-report report.html
```

Writes a single, self-contained HTML file -- inlined CSS/JS, no server, no CDN assets, nothing fetched over the network -- showing an interactive role → action → resource graph. Hover a role to trace everything it can reach; hover an edge for the underlying condition and confidence. Edges are solid green where `resolved`, dashed amber where `unsupported`, and solid red where a `--policy-file` check (if given) found a violation. A coverage line at the top mirrors the table's resolved/total summary. Only `allowed: true` results become edges -- it's a "who can access what" diagram, not a dump of every denial.

Combine it with `--policy-file` to get violations highlighted directly on the graph, not just listed in the table/JSON output. The file opens straight from disk (`file://`) in any browser -- no need to serve it.

## Security

`scan` executes code in `APP_PATH` -- it loads your `Ability` class (and anything that file requires) in a subprocess. Only run it against apps you trust. `inspect` is static analysis only (via Prism) and never executes the target.

`--html-report` makes no network requests, ever -- everything it needs is inlined into the one file it writes. It does embed your role names, action names, model names, and raw condition values into that file, though, so treat the generated report itself with the same care as the scan results: don't publish it somewhere untrusted people can read it if that data is sensitive.
