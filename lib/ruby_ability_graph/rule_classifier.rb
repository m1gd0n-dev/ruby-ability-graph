# frozen_string_literal: true

module RubyAbilityGraph
  # Classifies a single CanCan::Rule's condition:
  # "resolved" (unconditional or flat scalar hash, fully structured) or
  # "unsupported" (block, association-reaching, or otherwise opaque).
  # Shape only -- source/dynamic-generation handling lives in Enumerator.
  class RuleClassifier
    Classification = Struct.new(:confidence, :condition, :reason, :source, keyword_init: true)

    def self.call(rule:, model:)
      new(rule: rule, model: model).call
    end

    def initialize(rule:, model:)
      @rule = rule
      @model = model
    end

    def call
      # only_block?, not @rule.block -- cancancan only made `block` a public
      # reader from ~3.x on (it's a private ivar in, e.g., 1.17.0, still
      # bundled by real apps -- found via dogfooding dradis-ce). only_block?
      # (conditions_empty? && block-present) is public across both and, since
      # both versions treat a Hash-conditions-plus-block combo as a raise-on-
      # declaration error, it's equivalent to "has a block" for every rule
      # that could actually exist.
      return unsupported("block_condition") if @rule.only_block?

      conditions = @rule.conditions
      return resolved(nil) if blank?(conditions)
      return unsupported("unrecognized_condition_value") unless conditions.is_a?(Hash)

      classify_hash(conditions)
    end

    private

    def blank?(conditions)
      conditions.nil? || (conditions.respond_to?(:empty?) && conditions.empty?)
    end

    def classify_hash(conditions)
      conditions.each do |key, value|
        return unsupported("association_chained") if value.is_a?(Hash)
        return unsupported("requires_association_traversal") if association_key?(key)
        return unsupported("unrecognized_condition_value") unless scalar?(value)
      end
      resolved(conditions)
    end

    # Deliberately no special-casing by key name (e.g. tenant_id/team_id) --
    # a flat scalar comparison is resolved regardless of what it's called.
    def association_key?(key)
      @model.respond_to?(:reflect_on_association) && !@model.reflect_on_association(key).nil?
    end

    def scalar?(value)
      value.nil? || value == true || value == false ||
        value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(Symbol)
    end

    def resolved(condition)
      Classification.new(confidence: "resolved", condition: condition, reason: nil, source: nil)
    end

    def unsupported(reason)
      Classification.new(confidence: "unsupported", condition: nil, reason: reason, source: nil)
    end
  end
end
