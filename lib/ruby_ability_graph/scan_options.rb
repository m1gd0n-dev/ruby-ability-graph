# frozen_string_literal: true

require "optparse"

module RubyAbilityGraph
  # Parses and validates `scan` subcommand argv into an options hash + app
  # path. Split out from CLI so that class stays a thin command dispatcher
  # as flags accumulate (see .rubocop.yml's CLI Metrics/ClassLength note).
  class ScanOptions
    def self.parse(argv)
      new.parse(argv)
    end

    def parse(argv)
      options = defaults
      build_parser(options).parse!(argv)

      app_path = argv.shift
      abort(CLI::USAGE) unless app_path

      validate!(options)
      [options, app_path]
    end

    private

    def defaults
      {
        ability_file: Harness::DEFAULT_ABILITY_FILE, ability_class: "Ability",
        requires: [], rails_boot: false, format: "table"
      }
    end

    def build_parser(options)
      OptionParser.new do |opts|
        add_roles_file_option!(opts, options)
        add_ability_file_option!(opts, options)
        add_ability_class_option!(opts, options)
        add_ruby_bin_option!(opts, options)
        add_format_option!(opts, options)
        add_policy_file_option!(opts, options)
        add_html_report_option!(opts, options)
        add_loader_strategy_options!(opts, options)
      end
    end

    def add_roles_file_option!(opts, options)
      opts.on("--roles-file FILE", "YAML file mapping role name => user stand-in attributes") do |v|
        options[:roles_file] = v
      end
    end

    def add_ability_file_option!(opts, options)
      opts.on("--ability-file FILE", "Path to the Ability class file, relative to APP_PATH") do |v|
        options[:ability_file] = v
      end
    end

    def add_ability_class_option!(opts, options)
      opts.on("--ability-class NAME", "Constant name of the Ability class, e.g. Spree::Ability for a " \
                                       "namespaced/engine-provided one (default: Ability)") do |v|
        options[:ability_class] = v
      end
    end

    def add_ruby_bin_option!(opts, options)
      opts.on("--ruby-bin PATH", "Ruby executable for the target subprocess (default: " \
                                 "\"ruby\" via PATH); target can use a different Ruby version. " \
                                 "See README.") do |v|
        options[:ruby_bin] = v
      end
    end

    def add_format_option!(opts, options)
      opts.on("--format FORMAT", %w[table json], "Output format: table (default) or json") do |v|
        options[:format] = v
      end
    end

    def add_policy_file_option!(opts, options)
      opts.on("--policy-file FILE", "YAML file declaring role/action/model access expectations " \
                                    "(see README); violations are flagged and exit non-zero") do |v|
        options[:policy_file] = v
      end
    end

    def add_html_report_option!(opts, options)
      opts.on("--html-report FILE", "Write a self-contained, interactive HTML graph of the results " \
                                    "(see README) to this path, relative to APP_PATH") do |v|
        options[:html_report] = v
      end
    end

    def add_loader_strategy_options!(opts, options)
      add_require_option!(opts, options)
      add_rails_boot_option!(opts, options)
      add_rails_env_option!(opts, options)
    end

    def add_require_option!(opts, options)
      opts.on("--require FILE", "Path, relative to APP_PATH, to preload before the " \
                                "Ability file (repeatable), see #2. Not compatible " \
                                "with --rails-boot.") do |v|
        options[:requires] << v
      end
    end

    def add_rails_boot_option!(opts, options)
      opts.on("--rails-boot", "Run inside the target's own `bin/rails runner` for real " \
                              "Zeitwerk autoloading, see #3. Not compatible with --require.") do
        options[:rails_boot] = true
      end
    end

    def add_rails_env_option!(opts, options)
      opts.on("--rails-env ENV", "RAILS_ENV to boot under with --rails-boot (default: " \
                                 "#{Harness::DEFAULT_RAILS_ENV.inspect}).") do |v|
        options[:rails_env] = v
      end
    end

    def validate!(options)
      abort("--rails-env only applies with --rails-boot.") if options[:rails_env] && !options[:rails_boot]

      return unless options[:rails_boot] && !options[:requires].empty?

      abort("--require is not compatible with --rails-boot -- once Zeitwerk is live via bin/rails runner, " \
            "referenced classes resolve on their own; a manual --require list is superfluous. " \
            "Drop one or the other.")
    end
  end
end
