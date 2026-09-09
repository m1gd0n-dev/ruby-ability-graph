# frozen_string_literal: true

require "ruby_ability_graph"
require "yaml"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

def fixture_path(*parts)
  File.join(__dir__, "fixtures", *parts)
end

def roles_for(app_path)
  YAML.safe_load_file(File.join(app_path, ".ability_graph_roles.yml")).transform_values do |attrs|
    attrs.to_h { |k, v| [k.to_s.to_sym, v] }
  end
end

def result_for(results, role:, action:, model:)
  results.find { |r| r["role"] == role && r["action"] == action && r["model"] == model }
end

def with_env(vars)
  originals = vars.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
  vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  yield
ensure
  originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
end
