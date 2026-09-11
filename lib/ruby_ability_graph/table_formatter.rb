# frozen_string_literal: true

module RubyAbilityGraph
  # Renders scan results (role x action x model rows, string-keyed as they
  # come back from Harness) as a plain-text table -- the human-readable
  # counterpart to `--format json`, plus a resolved/unsupported coverage
  # summary line.
  class TableFormatter
    HEADERS = %w[ROLE ACTION MODEL ALLOWED CONFIDENCE CONDITION].freeze

    def self.call(results)
      new(results).call
    end

    def initialize(results)
      @results = results
    end

    def call
      rows = sorted_rows
      widths = column_widths(rows)
      table_lines = [format_row(HEADERS, widths), format_row(separator_cells(widths), widths)]
      rows.each { |row| table_lines << format_row(row, widths) }
      "#{table_lines.join("\n")}\n\n#{summary_line}"
    end

    private

    def sorted_rows
      @results.sort_by { |r| [r["role"], r["model"], r["action"]] }
              .map { |r| [r["role"], r["action"], r["model"], r["allowed"].to_s, r["confidence"], condition_cell(r)] }
    end

    def condition_cell(result)
      result["condition"].nil? ? "-" : result["condition"].to_s
    end

    def separator_cells(widths)
      widths.map { |w| "-" * w }
    end

    def column_widths(rows)
      HEADERS.each_index.map { |i| ([HEADERS[i].length] + rows.map { |r| r[i].to_s.length }).max }
    end

    def format_row(cells, widths)
      cells.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join("  ").rstrip
    end

    def summary_line
      resolved = @results.count { |r| r["confidence"] == "resolved" }
      total = @results.size
      "#{resolved}/#{total} resolved (#{coverage_pct(resolved, total)}%)"
    end

    def coverage_pct(resolved, total)
      return 0 if total.zero?

      ((resolved.to_f / total) * 100).round(1)
    end
  end
end
