# frozen_string_literal: true

require "json"
require_relative "table_formatter"
require_relative "terminal_safe"

module RubyAbilityGraph
  # Turns a scan's results (plus an optional PolicyChecker::Report) into the
  # CLI's printed output, in either format, and decides the process exit
  # status -- kept separate from CLI so that class stays a thin dispatcher.
  class ScanPresenter
    SCHEMA_VERSION = 1

    def initialize(format:, results:, policy_report:)
      @format = format
      @results = results
      @policy_report = policy_report
    end

    def render
      @format == "json" ? render_json : render_table
    end

    # nil policy_report means no --policy-file was given. An unmatched policy
    # (typo'd model/action) counts as a problem too, same as a real violation.
    def problems?
      !@policy_report.nil? && (@policy_report.violations.any? || @policy_report.unmatched.any?)
    end

    private

    def render_json
      payload = { "schema_version" => SCHEMA_VERSION, "results" => @results }
      if @policy_report
        payload["policy_violations"] = @policy_report.violations
        payload["policy_unmatched"] = @policy_report.unmatched
      end
      JSON.pretty_generate(payload)
    end

    def render_table
      return TableFormatter.call(@results) if @policy_report.nil?

      sections = [render_violations, render_unmatched].compact
      "#{TableFormatter.call(@results)}\n\n#{sections.join("\n\n")}"
    end

    def render_violations
      return "Policy check: no violations." if @policy_report.violations.empty?

      lines = ["Policy violations (#{@policy_report.violations.size}):"] +
              @policy_report.violations.map { |v| violation_line(v) }
      lines.join("\n")
    end

    def render_unmatched
      return nil if @policy_report.unmatched.empty?

      lines = ["Policy entries with no matching scan result -- check for typos " \
               "(#{@policy_report.unmatched.size}):"] + @policy_report.unmatched.map { |p| unmatched_line(p) }
      lines.join("\n")
    end

    def violation_line(violation)
      role, action, model = %w[role action model].map { |k| TerminalSafe.sanitize(violation[k]) }
      allowed_roles = violation["allowed_roles"].map { |r| TerminalSafe.sanitize(r) }.join(", ")
      "  #{role} can #{action} #{model} but is not in allowed_roles (#{allowed_roles}) [#{violation['confidence']}]"
    end

    def unmatched_line(policy)
      "  #{TerminalSafe.sanitize(policy['model'])} / #{TerminalSafe.sanitize(policy['action'])}"
    end
  end
end
