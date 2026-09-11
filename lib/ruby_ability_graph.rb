# frozen_string_literal: true

require_relative "ruby_ability_graph/version"
require_relative "ruby_ability_graph/role_stand_in"
require_relative "ruby_ability_graph/rule_classifier"
require_relative "ruby_ability_graph/enumerator"
require_relative "ruby_ability_graph/harness"
require_relative "ruby_ability_graph/inspector"
require_relative "ruby_ability_graph/table_formatter"
require_relative "ruby_ability_graph/policy_checker"
require_relative "ruby_ability_graph/scan_presenter"
require_relative "ruby_ability_graph/scan_options"
require_relative "ruby_ability_graph/cli"

module RubyAbilityGraph
  class Error < StandardError; end
end
