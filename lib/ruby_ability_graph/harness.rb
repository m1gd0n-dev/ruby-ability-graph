# frozen_string_literal: true

require "open3"
require "tempfile"
require "json"

module RubyAbilityGraph
  # Loads a target app's CanCanCan Ability class in a subprocess and reports
  # raw can?/cannot? results across the role x action x model cross-product.
  class Harness
    class LoadError < StandardError; end

    DEFAULT_ABILITY_FILE = "app/models/ability.rb"
    DEFAULT_RAILS_ENV = "test"
    MARKER = "RUBY_ABILITY_GRAPH_RESULT:"

    def initialize(app_path:, roles:, ability_file: DEFAULT_ABILITY_FILE, ability_class_name: "Ability", requires: [],
                   rails_boot: false, rails_env: DEFAULT_RAILS_ENV, ruby_bin: "ruby")
      validate_requires_compatibility!(rails_boot, requires)

      @app_path = File.expand_path(app_path)
      @roles = roles
      @ability_file = ability_file
      @ability_class_name = ability_class_name
      @requires = requires
      @rails_boot = rails_boot
      @rails_env = rails_env
      @ruby_bin = ruby_bin
    end

    def run
      Tempfile.create(["ruby_ability_graph_runner", ".rb"]) do |file|
        file.write(runner_script)
        file.flush
        stdout, stderr, status = execute(file.path)
        unless status.success?
          raise LoadError, "Failed to load and analyze #{@ability_class_name} in #{@app_path}:\n#{stderr}"
        end

        extract_results(stdout)
      end
    end

    private

    def validate_requires_compatibility!(rails_boot, requires)
      return unless rails_boot && !requires.empty?

      raise ArgumentError, "requires: is not compatible with rails_boot: -- once Zeitwerk is live via " \
                           "bin/rails runner, referenced classes resolve on their own; a manual requires: " \
                           "list is superfluous. Drop one or the other."
    end

    def execute(script_path)
      return execute_via_rails_runner(script_path) if @rails_boot

      command = bundler_project? ? ["bundle", "exec", @ruby_bin] : [@ruby_bin]
      # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec -- @ruby_bin/@app_path are caller-supplied
      # tool config, not untrusted remote input; spawning the target app is this harness's intended function.
      Open3.capture3(*command, script_path, chdir: @app_path)
    end

    def execute_via_rails_runner(script_path)
      rails_bin = File.join(@app_path, "bin", "rails")
      unless File.exist?(rails_bin)
        raise LoadError, "rails_boot: true but no bin/rails found in #{@app_path} -- this doesn't look like a " \
                         "Rails app."
      end

      # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec -- same rationale as execute/1 above.
      Open3.capture3({ "RAILS_ENV" => @rails_env }, @ruby_bin, "--", rails_bin, "runner", script_path,
                     chdir: @app_path)
    end

    def bundler_project?
      File.exist?(File.join(@app_path, "Gemfile"))
    end

    def require_lines(paths)
      paths.map { |path| "require #{path.inspect}" }.join("\n")
    end

    def extract_results(stdout)
      line = stdout.lines.rfind { |l| l.start_with?(MARKER) }
      raise LoadError, "RubyAbilityGraph runner produced no result.\n\nFull output:\n#{stdout}" unless line

      JSON.parse(line.sub(MARKER, ""))
    end

    def runner_script
      <<~RUBY
        require "json"
        require #{File.expand_path('role_stand_in.rb', __dir__).inspect}
        require #{File.expand_path('enumerator.rb', __dir__).inspect}
        #{ability_loading_lines}
        role_stand_ins = JSON.parse(#{@roles.to_json.inspect}).transform_values do |attrs|
          RubyAbilityGraph::RoleStandIn.new(attrs)
        end
        #{resolve_and_report_lines}
      RUBY
    end

    def resolve_and_report_lines
      <<~RUBY.chomp
        ability_class = Object.const_get(#{@ability_class_name.inspect})
        results = RubyAbilityGraph::Enumerator.call(ability_class: ability_class, role_stand_ins: role_stand_ins)
        puts #{MARKER.inspect} + results.map(&:to_h).to_json
      RUBY
    end

    def ability_loading_lines
      @rails_boot ? rails_boot_loading_lines : plain_require_loading_lines
    end

    def rails_boot_loading_lines
      "# rails_boot: true -- Ability file resolves via Zeitwerk autoloading, no explicit require needed. See #3."
    end

    def plain_require_loading_lines
      ability_path = File.expand_path(@ability_file, @app_path)
      require_paths = @requires.map { |path| File.expand_path(path, @app_path) }

      <<~RUBY
        require "cancancan"
        #{require_lines(require_paths)}
        require #{ability_path.inspect}
      RUBY
    end
  end
end
