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
                                               [--require FILE]... | [--rails-boot [--rails-env ENV]]
                                               [--ruby-bin PATH]
             ruby-ability-graph inspect APP_PATH [--ability-file FILE]
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
      options, app_path = parse_scan_args(argv)
      roles = load_roles(options[:roles_file], app_path)
      results = RubyAbilityGraph::Harness.new(**harness_kwargs(options, app_path, roles)).run
      puts JSON.pretty_generate("raw_results" => results)
    end

    def parse_scan_args(argv)
      options = { ability_file: RubyAbilityGraph::Harness::DEFAULT_ABILITY_FILE, requires: [], rails_boot: false }
      build_scan_option_parser(options).parse!(argv)

      app_path = argv.shift
      abort(USAGE) unless app_path

      validate_scan_options!(options)
      [options, app_path]
    end

    def harness_kwargs(options, app_path, roles)
      kwargs = {
        app_path: app_path,
        roles: roles,
        ability_file: options[:ability_file],
        requires: options[:requires],
        rails_boot: options[:rails_boot]
      }
      kwargs[:rails_env] = options[:rails_env] if options[:rails_env]
      kwargs[:ruby_bin] = options[:ruby_bin] if options[:ruby_bin]
      kwargs
    end

    def build_scan_option_parser(options)
      OptionParser.new do |opts|
        opts.on("--roles-file FILE", "YAML file mapping role name => user stand-in attributes") do |v|
          options[:roles_file] = v
        end
        add_ability_file_option!(opts, options)
        opts.on("--ruby-bin PATH", "Ruby executable for the target subprocess (default: " \
                                   "\"ruby\" via PATH); target can use a different Ruby version. " \
                                   "See README.") do |v|
          options[:ruby_bin] = v
        end
        add_loader_strategy_options!(opts, options)
      end
    end

    # Shared with `inspect`'s option parser -- both subcommands take the same --ability-file flag.
    def add_ability_file_option!(opts, options)
      opts.on("--ability-file FILE", "Path to the Ability class file, relative to APP_PATH") do |v|
        options[:ability_file] = v
      end
    end

    def add_loader_strategy_options!(opts, options)
      opts.on("--require FILE", "Path, relative to APP_PATH, to preload before the " \
                                "Ability file (repeatable), see #2. Not compatible " \
                                "with --rails-boot.") do |v|
        options[:requires] << v
      end
      opts.on("--rails-boot", "Run inside the target's own `bin/rails runner` for real " \
                              "Zeitwerk autoloading, see #3. Not compatible with --require.") do
        options[:rails_boot] = true
      end
      opts.on("--rails-env ENV", "RAILS_ENV to boot under with --rails-boot (default: " \
                                 "#{RubyAbilityGraph::Harness::DEFAULT_RAILS_ENV.inspect}).") do |v|
        options[:rails_env] = v
      end
    end

    def validate_scan_options!(options)
      abort("--rails-env only applies with --rails-boot.") if options[:rails_env] && !options[:rails_boot]

      return unless options[:rails_boot] && !options[:requires].empty?

      abort("--require is not compatible with --rails-boot -- once Zeitwerk is live via bin/rails runner, " \
            "referenced classes resolve on their own; a manual --require list is superfluous. " \
            "Drop one or the other.")
    end

    def inspect_ability(argv)
      app_path, ability_file = parse_inspect_args(argv)
      inspector = RubyAbilityGraph::Inspector.new(ability_file: File.expand_path(ability_file, app_path))

      result = begin
        inspector.call
      rescue RubyAbilityGraph::Inspector::InspectionError => e
        abort(e.message)
      end

      print_inspection_result(result)
    end

    def parse_inspect_args(argv)
      options = { ability_file: RubyAbilityGraph::Harness::DEFAULT_ABILITY_FILE }
      OptionParser.new do |opts|
        add_ability_file_option!(opts, options)
      end.parse!(argv)

      app_path = argv.shift
      abort(USAGE) unless app_path
      [app_path, options[:ability_file]]
    end

    def print_inspection_result(result)
      puts "Methods called on `user` in Ability#initialize:"
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
