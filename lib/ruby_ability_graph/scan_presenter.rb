# frozen_string_literal: true

require "json"
require_relative "table_formatter"

module RubyAbilityGraph
  # Turns a scan's results (plus optional policy-check violations) into the
  # CLI's printed output, in either format, and decides the process exit
  # status -- kept separate from CLI so that class stays a thin dispatcher.
  class ScanPresenter
    SCHEMA_VERSION = 1

    def initialize(format:, results:, violations:)
      @format = format
      @results = results
      @violations = violations
    end

    def render
      @format == "json" ? render_json : render_table
    end

    # `violations` is nil when no --policy-file was given -- distinct from
    # an empty array, which means the policy file passed clean.
    def violations?
      !@violations.nil? && !@violations.empty?
    end

    private

    def render_json
      payload = { "schema_version" => SCHEMA_VERSION, "results" => @results }
      payload["policy_violations"] = @violations unless @violations.nil?
      JSON.pretty_generate(payload)
    end

    def render_table
      return TableFormatter.call(@results) if @violations.nil?

      "#{TableFormatter.call(@results)}\n\n#{render_violations}"
    end

    def render_violations
      return "Policy check: no violations." if @violations.empty?

      lines = ["Policy violations (#{@violations.size}):"] + @violations.map { |v| violation_line(v) }
      lines.join("\n")
    end

    def violation_line(violation)
      "  #{violation['role']} can #{violation['action']} #{violation['model']} but is not in allowed_roles " \
        "(#{violation['allowed_roles'].join(', ')}) [#{violation['confidence']}]"
    end
  end
end
