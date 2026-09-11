# frozen_string_literal: true

module RubyAbilityGraph
  # Diffs resolved scan results against a simple YAML policy declaration
  # ("only `admin` may access `Payment` records") and flags roles that can
  # actually reach something the policy doesn't expect. Policy language is
  # deliberately flat -- model + action + allowed_roles, no nested logic.
  class PolicyChecker
    def self.call(policies:, results:)
      new(policies: policies, results: results).call
    end

    def initialize(policies:, results:)
      @policies = policies
      @results = results
    end

    def call
      @policies.flat_map { |policy| violations_for(policy) }
    end

    private

    def violations_for(policy)
      model = policy["model"].to_s
      action = policy["action"].to_s
      allowed_roles = Array(policy["allowed_roles"]).map(&:to_s)

      matching_results(model, action)
        .select { |r| r["allowed"] && !allowed_roles.include?(r["role"]) }
        .map { |r| build_violation(r, allowed_roles) }
    end

    def matching_results(model, action)
      @results.select { |r| r["model"] == model && r["action"] == action }
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
