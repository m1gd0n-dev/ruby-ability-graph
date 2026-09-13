# frozen_string_literal: true

require "optparse"
require "yaml"
require "json"

module RubyAbilityGraph
  # Command-line entry point: `scan` runs the role x action x model analysis
  # via Harness, `inspect` runs the roles-file authoring aid via Inspector.
  class CLI
    USAGE = <<~USAGE.chomp
      Usage: ruby-ability-graph scan APP_PATH [--roles-file FILE] [--ability-file FILE]
                                               [--ability-class NAME]
                                               [--require FILE]... | [--rails-boot [--rails-env ENV]]
                                               [--ruby-bin PATH] [--format table|json] [--policy-file FILE]
                                               [--html-report FILE]
             ruby-ability-graph inspect APP_PATH [--ability-file FILE] [--ability-class NAME]
    USAGE

    def self.start(argv)
      new.run(argv)
    end

    def run(argv)
      command, *rest = argv
      case command
      when "scan" then scan(rest)
      when "inspect" then inspect_ability(rest)
      else warn USAGE and exit(1)
      end
    end

    private

    def scan(argv)
      options, app_path = RubyAbilityGraph::ScanOptions.parse(argv)
      roles = load_roles(options[:roles_file], app_path)
      results = RubyAbilityGraph::Harness.new(**harness_kwargs(options, app_path, roles)).run
      violations = load_policy_violations(options[:policy_file], app_path, results)
      output_results(options, app_path, results, violations)
    end

    def output_results(options, app_path, results, violations)
      write_html_report(options[:html_report], app_path, results, violations)

      presenter = RubyAbilityGraph::ScanPresenter.new(
        format: options[:format], results: results, violations: violations
      )
      puts presenter.render
      exit(1) if presenter.violations?
    end

    # rails_env/ruby_bin are only included when set at all, so Harness's own
    # keyword defaults apply otherwise -- an explicit nil would override
    # them instead. #compact drops both when absent (rails_boot: false is a
    # real value, not "absent", so it survives).
    def harness_kwargs(options, app_path, roles)
      {
        app_path: app_path, roles: roles, ability_file: options[:ability_file],
        ability_class_name: options[:ability_class], requires: options[:requires],
        rails_boot: options[:rails_boot], rails_env: options[:rails_env], ruby_bin: options[:ruby_bin]
      }.compact
    end

    # nil (not merely empty) means "no --policy-file given" -- ScanPresenter
    # uses that distinction to decide whether to print a policy section at all.
    def load_policy_violations(policy_file, app_path, results)
      return nil unless policy_file

      path = File.expand_path(policy_file, app_path)
      abort("No policy file found at #{path}.") unless File.exist?(path)

      policies = YAML.safe_load_file(path)["policies"] || []
      RubyAbilityGraph::PolicyChecker.call(policies: policies, results: results)
    end

    # Written to stderr, not stdout -- keeps `--format json` pipeable without
    # this confirmation line landing in the middle of the JSON payload.
    def write_html_report(html_report, app_path, results, violations)
      return unless html_report

      path = File.expand_path(html_report, app_path)
      File.write(path, RubyAbilityGraph::HtmlReport.call(results: results, violations: violations))
      warn "HTML report written to #{path}"
    end

    def inspect_ability(argv)
      app_path, options = parse_inspect_args(argv)
      inspector = build_inspector(options, app_path)
      result = run_inspector(inspector)
      print_inspection_result(result, options[:ability_class])
    end

    def build_inspector(options, app_path)
      RubyAbilityGraph::Inspector.new(
        ability_file: File.expand_path(options[:ability_file], app_path),
        ability_class_name: options[:ability_class]
      )
    end

    def run_inspector(inspector)
      inspector.call
    rescue RubyAbilityGraph::Inspector::InspectionError => e
      abort(e.message)
    end

    def parse_inspect_args(argv)
      options = { ability_file: RubyAbilityGraph::Harness::DEFAULT_ABILITY_FILE, ability_class: "Ability" }
      build_inspect_parser(options).parse!(argv)

      app_path = argv.shift
      abort(USAGE) unless app_path
      [app_path, options]
    end

    ABILITY_CLASS_HELP = "The class name exactly as written at its `class` statement in that file -- " \
                         "usually just Ability even when it's namespaced (e.g. `module Spree; class " \
                         "Ability`), unless it's written inline as `class Spree::Ability` (default: Ability)"
    private_constant :ABILITY_CLASS_HELP

    def build_inspect_parser(options)
      OptionParser.new do |opts|
        opts.on("--ability-file FILE", "Path to the Ability class file, relative to APP_PATH") do |v|
          options[:ability_file] = v
        end
        opts.on("--ability-class NAME", ABILITY_CLASS_HELP) { |v| options[:ability_class] = v }
      end
    end

    def print_inspection_result(result, ability_class)
      puts "Methods called on `user` in #{ability_class}#initialize:"
      result.method_names.each { |m| puts "  #{m}" }
      puts
      puts "Your roles file needs a value for each, per role that reaches it."
      puts
      puts "Warning: #{result.warning}" if result.warning
    end

    def load_roles(roles_file, app_path)
      path = roles_file || File.join(app_path, ".ability_graph_roles.yml")
      unless File.exist?(path)
        abort("No roles file found at #{path}. Pass --roles-file or add .ability_graph_roles.yml to the app root.")
      end
      YAML.safe_load_file(path, permitted_classes: [Symbol]).transform_values do |attrs|
        (attrs || {}).to_h { |k, v| [k.to_s.to_sym, v] }
      end
    end
  end
end
