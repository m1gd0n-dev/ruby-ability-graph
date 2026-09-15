# frozen_string_literal: true

require "json"

module RubyAbilityGraph
  # Renders scan results (plus optional policy-check violations) as a single
  # self-contained HTML file: an interactive role -> action -> resource graph,
  # edges colored/dashed by confidence and flagged where a policy violation
  # applies. No server, no external requests, no CDN assets -- everything
  # (CSS, JS, data) is inlined so the file opens straight from disk. That
  # matches the README's trust story: this tool runs locally and never phones
  # home, and the report it produces shouldn't either.
  #
  # Untrusted data (role/action/model names, raw conditions) comes from the
  # scanned app's own source, so it's only ever passed through as JSON and
  # rendered client-side via textContent/DOM APIs -- never interpolated into
  # HTML or innerHTML -- to avoid the report becoming an XSS vector against
  # whoever opens it.
  class HtmlReport
    DATA_PLACEHOLDER = "/*__RUBY_ABILITY_GRAPH_DATA__*/"

    # The quoted heredoc delimiter isn't about interpolation -- there's no
    # Ruby interpolation syntax anywhere below. It's what stops Ruby from
    # interpreting the embedded JS's own backslash escape sequences as if
    # they were Ruby's own string escapes.
    TEMPLATE = <<~'HTML'
      <!doctype html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Ruby Ability Graph Report</title>
      <style>
        :root {
          color-scheme: light;
          --surface:   #fcfcfb;
          --plane:     #f9f9f7;
          --ink:       #0b0b0b;
          --ink-2:     #52514e;
          --muted:     #898781;
          --grid:      #e1e0d9;
          --border:    rgba(11,11,11,0.10);
          --good:      #0ca30c;
          --warning:   #fab219;
          --critical:  #d03b3b;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            color-scheme: dark;
            --surface:  #1a1a19;
            --plane:    #0d0d0d;
            --ink:      #ffffff;
            --ink-2:    #c3c2b7;
            --muted:    #898781;
            --grid:     #2c2c2a;
            --border:   rgba(255,255,255,0.10);
          }
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          background: var(--plane);
          color: var(--ink);
          font: 14px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif;
        }
        header, footer { padding: 20px 24px; }
        header h1 { margin: 0 0 4px; font-size: 18px; }
        header p { margin: 0; color: var(--ink-2); }
        #summary { display: flex; gap: 24px; flex-wrap: wrap; margin-top: 12px; }
        #summary div { color: var(--ink-2); }
        #summary strong { color: var(--ink); }
        #legend { display: flex; gap: 20px; flex-wrap: wrap; margin-top: 14px; font-size: 13px; color: var(--ink-2); }
        #legend span { display: inline-flex; align-items: center; gap: 6px; }
        .swatch { display: inline-block; width: 22px; height: 0; border-top-width: 3px; border-top-style: solid; }
        .swatch.resolved { border-color: var(--good); border-top-style: solid; }
        .swatch.partial { height: 3px; border-top: none; background: linear-gradient(to right, var(--warning), var(--good)); }
        .swatch.unsupported { border-color: var(--warning); border-top-style: dashed; }
        .swatch.violation { border-color: var(--critical); border-top-style: solid; }
        main {
          margin: 0 24px 24px;
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: 8px;
          overflow: auto;
          max-height: 80vh;
        }
        svg { display: block; width: 100%; height: auto; }
        .node circle { fill: var(--surface); stroke: var(--muted); stroke-width: 1.5px; }
        .node text { fill: var(--ink-2); font-size: 12px; }
        .node.active circle { stroke: var(--ink); stroke-width: 2px; }
        .node.active text { fill: var(--ink); }
        .edge { fill: none; stroke-width: 2px; cursor: pointer; }
        .edge.resolved { stroke: var(--good); }
        .edge.unsupported { stroke: var(--warning); stroke-dasharray: 6 4; }
        .edge.violation { stroke: var(--critical); stroke-width: 3px; }
        svg.hovering .node, svg.hovering .edge { opacity: 0.15; transition: opacity 0.12s; }
        svg.hovering .active { opacity: 1; }
        #empty { padding: 40px; text-align: center; color: var(--muted); }
        #tooltip {
          position: fixed;
          display: none;
          max-width: 320px;
          padding: 8px 10px;
          background: var(--surface);
          color: var(--ink);
          border: 1px solid var(--border);
          border-radius: 6px;
          box-shadow: 0 4px 16px rgba(0,0,0,0.18);
          font-size: 12px;
          pointer-events: none;
          z-index: 10;
          white-space: pre-line;
        }
        footer { color: var(--muted); font-size: 12px; }
      </style>
      </head>
      <body>
        <header>
          <h1>Ruby Ability Graph Report</h1>
          <p>Role &rarr; action &rarr; resource, from a ruby_ability_graph scan. Hover a node to trace its reach, hover an edge for detail.</p>
          <div id="summary">
            <div id="coverage-line"></div>
            <div id="violation-line"></div>
          </div>
          <div id="legend">
            <span><span class="swatch resolved"></span> Resolved</span>
            <span><span class="swatch partial"></span> Bundled edge, partially resolved -- color shows % resolved</span>
            <span><span class="swatch unsupported"></span> Unsupported -- not analyzed</span>
            <span><span class="swatch violation"></span> Policy violation</span>
          </div>
        </header>
        <main>
          <svg id="graph" viewBox="0 0 960 400" role="img" aria-label="Role to action to resource access graph"></svg>
          <div id="empty" hidden>No allowed role &times; action &times; resource combinations found.</div>
        </main>
        <footer>Generated locally by ruby_ability_graph. This file contains no external requests -- open it offline.</footer>
        <div id="tooltip"></div>
        <script>
        (function () {
          "use strict";
          var DATA = /*__RUBY_ABILITY_GRAPH_DATA__*/;
          var SVGNS = "http://www.w3.org/2000/svg";
          // A control character, not a display separator -- joins role/action/model
          // names into map keys so a name that happens to contain a plain space
          // can't collide with a different (role, action) or (action, model) pair.
          // Built at runtime (not written as a literal escape) so it stays a plain
          // JS string, unambiguous from Ruby's own escape handling of this template.
          var SEP = String.fromCharCode(0);
          var ROW_HEIGHT = 28;
          var WIDTH = 960;
          var MARGIN = 110;

          function svgEl(name, attrs) {
            var el = document.createElementNS(SVGNS, name);
            for (var k in attrs) { el.setAttribute(k, attrs[k]); }
            return el;
          }

          function uniqueSorted(values) {
            return Array.from(new Set(values)).sort();
          }

          function positions(names, height) {
            var step = height / (names.length + 1);
            var map = {};
            names.forEach(function (name, i) { map[name] = step * (i + 1); });
            return map;
          }

          // Aggregated edges bundle many rows (e.g. a role->action edge spans every
          // model that pair touches). A single boolean verdict for the whole bundle
          // is misleading at scale: one unsupported row among sixty resolved ones
          // painted the entire edge amber. Color proportionally instead, so an
          // edge that's mostly resolved reads as mostly green.
          var COLOR_WARNING = [250, 178, 25]; // --warning, #fab219
          var COLOR_GOOD = [12, 163, 12]; // --good, #0ca30c

          function resolvedFraction(rows) {
            var resolved = rows.filter(function (r) { return r.confidence === "resolved"; }).length;
            return resolved / rows.length;
          }

          function mixColor(fraction) {
            var rgb = COLOR_WARNING.map(function (c, i) { return Math.round(c + (COLOR_GOOD[i] - c) * fraction); });
            return "rgb(" + rgb.join(",") + ")";
          }

          function edgeAppearance(rows) {
            if (rows.some(function (r) { return r.violation; })) { return { cls: "violation" }; }
            var fraction = resolvedFraction(rows);
            if (fraction === 1) { return { cls: "resolved" }; }
            if (fraction === 0) { return { cls: "unsupported" }; }
            return { cls: "partial", style: "stroke:" + mixColor(fraction) + ";" };
          }

          function groupBy(rows, keyFn, shapeFn) {
            var map = new Map();
            rows.forEach(function (row) {
              var key = keyFn(row);
              if (!map.has(key)) { map.set(key, shapeFn(row)); }
              map.get(key).rows.push(row);
            });
            return Array.from(map.values());
          }

          function byField(edges, field) {
            var map = {};
            edges.forEach(function (edge) {
              (map[edge[field]] = map[edge[field]] || []).push(edge);
            });
            return map;
          }

          function fillCoverage() {
            var c = DATA.coverage;
            document.getElementById("coverage-line").innerHTML =
              "<strong>" + c.resolved + "/" + c.total + "</strong> resolved (" + c.pct + "%)";
            var v = document.getElementById("violation-line");
            if (DATA.violationCount === null || DATA.violationCount === undefined) {
              v.textContent = "No policy file was checked.";
            } else if (DATA.violationCount === 0) {
              v.textContent = "Policy check: no violations.";
            } else {
              v.textContent = DATA.violationCount + " policy violation(s) -- highlighted in red below.";
            }
          }

          function render() {
            fillCoverage();
            var rows = DATA.rows;
            var svg = document.getElementById("graph");
            if (!rows.length) {
              svg.setAttribute("hidden", "hidden");
              document.getElementById("empty").hidden = false;
              return;
            }

            var roles = uniqueSorted(rows.map(function (r) { return r.role; }));
            var actions = uniqueSorted(rows.map(function (r) { return r.action; }));
            var models = uniqueSorted(rows.map(function (r) { return r.model; }));
            var height = Math.max(360, (Math.max(roles.length, actions.length, models.length) + 1) * ROW_HEIGHT);

            svg.setAttribute("viewBox", "0 0 " + WIDTH + " " + height);
            var roleX = MARGIN, actionX = WIDTH / 2, modelX = WIDTH - MARGIN;
            var roleY = positions(roles, height), actionY = positions(actions, height), modelY = positions(models, height);

            var raEdges = groupBy(
              rows,
              function (r) { return r.role + SEP + r.action; },
              function (r) { return { role: r.role, action: r.action, rows: [] }; }
            );
            var amEdges = groupBy(
              rows,
              function (r) { return r.action + SEP + r.model; },
              function (r) { return { action: r.action, model: r.model, rows: [] }; }
            );
            var raByRole = byField(raEdges, "role"), raByAction = byField(raEdges, "action");
            var amByAction = byField(amEdges, "action"), amByModel = byField(amEdges, "model");

            var elements = { role: {}, action: {}, model: {}, ra: {}, am: {} };

            function edgeKey(edge, a, b) { return edge[a] + SEP + edge[b]; }

            function drawEdge(x1, y1, x2, y2, statusRows, store, key) {
              var midX = (x1 + x2) / 2;
              var appearance = edgeAppearance(statusRows);
              var attrs = {
                "class": "edge " + appearance.cls,
                d: "M " + x1 + "," + y1 + " C " + midX + "," + y1 + " " + midX + "," + y2 + " " + x2 + "," + y2
              };
              if (appearance.style) { attrs.style = appearance.style; }
              var path = svgEl("path", attrs);
              svg.appendChild(path);
              store[key] = path;
              return path;
            }

            raEdges.forEach(function (edge) {
              var key = edgeKey(edge, "role", "action");
              var path = drawEdge(roleX, roleY[edge.role], actionX, actionY[edge.action], edge.rows, elements.ra, key);
              path.addEventListener("mouseenter", function (ev) { hoverRoleAction(edge); showTooltip(ev, raTooltip(edge)); });
              path.addEventListener("mousemove", function (ev) { moveTooltip(ev); });
              path.addEventListener("mouseleave", clearHover);
            });

            amEdges.forEach(function (edge) {
              var key = edgeKey(edge, "action", "model");
              var path = drawEdge(actionX, actionY[edge.action], modelX, modelY[edge.model], edge.rows, elements.am, key);
              path.addEventListener("mouseenter", function (ev) { hoverActionModel(edge); showTooltip(ev, amTooltip(edge)); });
              path.addEventListener("mousemove", function (ev) { moveTooltip(ev); });
              path.addEventListener("mouseleave", clearHover);
            });

            function drawNode(name, x, y, kind, anchor, store, onHover) {
              var g = svgEl("g", { "class": "node " + kind });
              var circle = svgEl("circle", { cx: x, cy: y, r: 5 });
              var title = document.createElementNS(SVGNS, "title");
              title.textContent = name;
              circle.appendChild(title);
              var text = svgEl("text", {
                x: x + (anchor === "end" ? -10 : anchor === "start" ? 10 : 0),
                y: anchor === "middle" ? y - 10 : y + 4,
                "text-anchor": anchor
              });
              text.textContent = name;
              g.appendChild(circle);
              g.appendChild(text);
              g.addEventListener("mouseenter", onHover);
              g.addEventListener("mouseleave", clearHover);
              svg.appendChild(g);
              store[name] = g;
            }

            roles.forEach(function (name) {
              drawNode(name, roleX, roleY[name], "role", "end", elements.role, function () { hoverRole(name); });
            });
            actions.forEach(function (name) {
              drawNode(name, actionX, actionY[name], "action", "middle", elements.action, function () { hoverAction(name); });
            });
            models.forEach(function (name) {
              drawNode(name, modelX, modelY[name], "model", "start", elements.model, function () { hoverModel(name); });
            });

            function activate(roleNames, actionNames, modelNames, raList, amList) {
              svg.classList.add("hovering");
              Array.from(svg.querySelectorAll(".active")).forEach(function (el) { el.classList.remove("active"); });
              roleNames.forEach(function (n) { elements.role[n] && elements.role[n].classList.add("active"); });
              actionNames.forEach(function (n) { elements.action[n] && elements.action[n].classList.add("active"); });
              modelNames.forEach(function (n) { elements.model[n] && elements.model[n].classList.add("active"); });
              raList.forEach(function (e) { elements.ra[edgeKey(e, "role", "action")].classList.add("active"); });
              amList.forEach(function (e) { elements.am[edgeKey(e, "action", "model")].classList.add("active"); });
            }

            function clearHover() {
              svg.classList.remove("hovering");
              Array.from(svg.querySelectorAll(".active")).forEach(function (el) { el.classList.remove("active"); });
              hideTooltip();
            }

            function hoverRole(role) {
              var ra = raByRole[role] || [];
              var actionNames = uniqueSorted(ra.map(function (e) { return e.action; }));
              var am = [];
              actionNames.forEach(function (a) { am = am.concat(amByAction[a] || []); });
              var modelNames = uniqueSorted(am.map(function (e) { return e.model; }));
              activate([role], actionNames, modelNames, ra, am);
            }

            function hoverAction(action) {
              var ra = raByAction[action] || [];
              var am = amByAction[action] || [];
              activate(uniqueSorted(ra.map(function (e) { return e.role; })), [action],
                       uniqueSorted(am.map(function (e) { return e.model; })), ra, am);
            }

            function hoverModel(model) {
              var am = amByModel[model] || [];
              var actionNames = uniqueSorted(am.map(function (e) { return e.action; }));
              var ra = [];
              actionNames.forEach(function (a) { ra = ra.concat(raByAction[a] || []); });
              activate(uniqueSorted(ra.map(function (e) { return e.role; })), actionNames, [model], ra, am);
            }

            function hoverRoleAction(edge) {
              activate([edge.role], [edge.action], uniqueSorted(edge.rows.map(function (r) { return r.model; })),
                       [edge], []);
            }

            function hoverActionModel(edge) {
              activate(uniqueSorted(edge.rows.map(function (r) { return r.role; })), [edge.action], [edge.model],
                       [], [edge]);
            }

            function rowLine(label, row) {
              var bits = [label + ": " + row.confidence];
              if (row.condition !== null && row.condition !== undefined) { bits.push(JSON.stringify(row.condition)); }
              if (row.reasons && row.reasons.length) { bits.push("(" + row.reasons.join(", ") + ")"); }
              if (row.violation) { bits.push("⚠ policy violation"); }
              return bits.join(" ");
            }

            function edgeHeader(a, b, rows) {
              var resolved = rows.filter(function (r) { return r.confidence === "resolved"; }).length;
              var header = a + " → " + b + " -- " + resolved + "/" + rows.length + " resolved";
              var violationCount = rows.filter(function (r) { return r.violation; }).length;
              if (violationCount) { header += ", " + violationCount + " violation(s)"; }
              return header;
            }

            function raTooltip(edge) {
              return [edgeHeader(edge.role, edge.action, edge.rows)]
                .concat(edge.rows.map(function (r) { return rowLine(r.model, r); }))
                .join("\n");
            }

            function amTooltip(edge) {
              return [edgeHeader(edge.action, edge.model, edge.rows)]
                .concat(edge.rows.map(function (r) { return rowLine(r.role, r); }))
                .join("\n");
            }
          }

          var tooltip = document.getElementById("tooltip");

          function showTooltip(ev, text) {
            tooltip.textContent = text;
            tooltip.style.display = "block";
            moveTooltip(ev);
          }

          function moveTooltip(ev) {
            tooltip.style.left = (ev.clientX + 14) + "px";
            tooltip.style.top = (ev.clientY + 14) + "px";
          }

          function hideTooltip() {
            tooltip.style.display = "none";
          }

          render();
        })();
        </script>
      </body>
      </html>
    HTML

    def self.call(results:, violations: nil)
      new(results: results, violations: violations).call
    end

    def initialize(results:, violations: nil)
      @results = results
      @violations = violations
    end

    def call
      # Block form, not TEMPLATE.sub(DATA_PLACEHOLDER, embedded_json) -- a String
      # replacement argument gets backreference processing (\1, \&, ...), which
      # would silently mangle JSON containing backslashes (e.g. our own "<\/"
      # escaping below, or a condition value with a literal backslash in it).
      # The block form inserts its return value verbatim.
      TEMPLATE.sub(DATA_PLACEHOLDER) { embedded_json }
    end

    private

    # Escape "</" so a condition value containing a literal "</script>"
    # can't break out of the inline <script> block it's embedded in.
    def embedded_json
      data.to_json.gsub("</", '<\/')
    end

    def data
      { "rows" => allowed_rows, "coverage" => coverage, "violationCount" => @violations&.size }
    end

    # Only allowed=true rows are graph-worthy -- this is a "who can access
    # what" diagram, not a dump of every denial.
    def allowed_rows
      violated = violated_triples
      @results.select { |r| r["allowed"] }.map do |r|
        {
          "role" => r["role"], "action" => r["action"], "model" => r["model"],
          "confidence" => r["confidence"], "condition" => r["condition"], "reasons" => r["reasons"] || [],
          "violation" => violated.include?([r["role"], r["action"], r["model"]])
        }
      end
    end

    def violated_triples
      (@violations || []).to_set { |v| [v["role"], v["action"], v["model"]] }
    end

    def coverage
      resolved = @results.count { |r| r["confidence"] == "resolved" }
      total = @results.size
      { "resolved" => resolved, "total" => total, "pct" => coverage_pct(resolved, total) }
    end

    def coverage_pct(resolved, total)
      return 0 if total.zero?

      ((resolved.to_f / total) * 100).round(1)
    end
  end
end
