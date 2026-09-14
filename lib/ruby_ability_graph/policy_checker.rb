# frozen_string_literal: true

module RubyAbilityGraph
  # Diffs resolved scan results against a simple YAML policy declaration
  # ("only `admin` may access `Payment` records") and flags roles that can
  # actually reach something the policy doesn't expect. Policy language is
  # deliberately flat -- model + action + allowed_roles, no nested logic.
  class PolicyChecker
    # unmatched: policies whose model/action matched zero scan results (e.g. a
    # typo) -- kept separate from violations so that case can't read as "clean".
    Report = Struct.new(:violations, :unmatched, keyword_init: true)

    def self.call(policies:, results:)
      new(policies: policies, results: results).call
    end

    def initialize(policies:, results:)
      @policies = policies
      @results = results
    end

    def call
      violations = []
      unmatched = []

      @policies.each do |policy|
        matches = matching_results(policy)
        matches.empty? ? unmatched << policy : violations.concat(violations_for(policy, matches))
      end

      Report.new(violations: violations, unmatched: unmatched)
    end

    private

    def matching_results(policy)
      model = policy["model"].to_s
      action = policy["action"].to_s
      @results.select { |r| r["model"] == model && r["action"] == action }
    end

    def violations_for(policy, matches)
      allowed_roles = Array(policy["allowed_roles"]).map(&:to_s)
      matches.select { |r| r["allowed"] && !allowed_roles.include?(r["role"]) }
             .map { |r| build_violation(r, allowed_roles) }
    end

    def build_violation(result, allowed_roles)
      {
        "model" => result["model"],
        "action" => result["action"],
        "role" => result["role"],
        "allowed_roles" => allowed_roles,
        "confidence" => result["confidence"],
        "condition" => result["condition"]
      }
    end
  end
end
