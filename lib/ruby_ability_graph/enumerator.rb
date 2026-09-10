# frozen_string_literal: true

require_relative "rule_classifier"

module RubyAbilityGraph
  # Runs a loaded Ability class's can? checks across every role x declared
  # action x declared model combination, classifying each result as
  # resolved/unsupported (per RuleClassifier + v1scopespec.md) rather than
  # returning a bare boolean.
  class Enumerator
    Result = Struct.new(:role, :action, :model, :allowed, :confidence, :condition, :reasons, :sources,
                         keyword_init: true)
    DEFAULT_ACTIONS = %i[index show create update destroy manage read].freeze

    # Records where each rule was declared, by wrapping CanCan::Ability's own
    # rule-append point. Lets unsupported results point back to source, and
    # lets us notice the same line firing more than once per instantiation --
    # a direct signal of loop-built rules (v1scopespec.md #2 item 4).
    module RuleSourceRecording
      def add_rule(rule)
        (@rag_rule_sources ||= []) << caller_locations.find { |loc| !loc.path.include?("cancancan") }
        super
      end
    end
    private_constant :RuleSourceRecording

    def self.call(ability_class:, role_stand_ins:)
      new(ability_class: ability_class, role_stand_ins: role_stand_ins).call
    end

    def initialize(ability_class:, role_stand_ins:)
      @ability_class = ability_class
      @role_stand_ins = role_stand_ins
    end

    def call
      ensure_source_recording!
      abilities = @role_stand_ins.transform_values { |user| @ability_class.new(user) }
      models = declared_models(abilities.values)
      actions = declared_actions(abilities.values)

      build_results(abilities, models, actions)
    end

    private

    # No-op if the target's CanCan::Ability doesn't expose #add_rule --
    # source/dynamic-generation data is simply unavailable then, not fatal.
    def ensure_source_recording!
      return if @ability_class.ancestors.include?(RuleSourceRecording)
      return unless @ability_class.method_defined?(:add_rule) || @ability_class.private_method_defined?(:add_rule)

      @ability_class.prepend(RuleSourceRecording)
    end

    def build_results(abilities, models, actions)
      results = []
      abilities.each do |role, ability|
        rule_sources = ability.instance_variable_get(:@rag_rule_sources) || []
        dynamic_indices = dynamic_rule_indices(rule_sources)
        models.each do |model|
          actions.each { |action| results << build_result(role, ability, model, action, rule_sources, dynamic_indices) }
        end
      end
      results
    end

    # Indices of rules whose declaration line was hit more than once for
    # this instantiation -- i.e. built in a loop, not a one-off `can` call.
    def dynamic_rule_indices(rule_sources)
      located = rule_sources.each_with_index.reject { |loc, _| loc.nil? }
      located.group_by { |loc, _| [loc.path, loc.lineno] }
             .values
             .select { |group| group.size > 1 }
             .flat_map { |group| group.map { |_, idx| idx } }
             .to_set
    end

    def build_result(role, ability, model, action, rule_sources, dynamic_indices)
      contributing = relevant_rules(ability, action, model)
      classifications = contributing.map { |rule, index| classify(rule, model, index, rule_sources, dynamic_indices) }

      Result.new(
        role: role.to_s,
        action: action.to_s,
        model: model_name(model),
        allowed: ability.can?(action, model),
        **verdict(classifications)
      )
    end

    def classify(rule, model, index, rule_sources, dynamic_indices)
      if dynamic_indices.include?(index)
        return RuleClassifier::Classification.new(confidence: "unsupported", condition: nil,
                                                    reason: "dynamic_rule_generation",
                                                    source: source_snippet(rule_sources[index]))
      end

      classification = RuleClassifier.call(rule: rule, model: model)
      classification.source = source_snippet(rule_sources[index]) if classification.confidence == "unsupported"
      classification
    end

    # Per v1scopespec.md #1 item 7: every rule contributing to this
    # (action, model) pair must itself be resolved for the combined result
    # to be resolved -- we trust can? for the boolean, not our own guess at
    # resolution order.
    def verdict(classifications)
      unsupported = classifications.reject { |c| c.confidence == "resolved" }
      return resolved_verdict(classifications) if unsupported.empty?

      {
        confidence: "unsupported",
        condition: nil,
        reasons: unsupported.map(&:reason).uniq,
        sources: unsupported.map(&:source).compact
      }
    end

    def resolved_verdict(classifications)
      conditions = classifications.filter_map(&:condition)
      condition = conditions.empty? ? nil : (conditions.size == 1 ? conditions.first : conditions)
      { confidence: "resolved", condition: condition, reasons: [], sources: [] }
    end

    # Rules whose action/subject match this (action, model) pair, regardless
    # of whether their condition currently evaluates true or false -- any one
    # of them being unsupported taints the whole pair (see #verdict).
    def relevant_rules(ability, action, model)
      rules = ability.send(:rules)
      candidates = if ability.respond_to?(:relevant_rules, true)
                     ability.send(:relevant_rules, action, model)
                   else
                     rules.select { |r| naive_relevant?(r, action, model) }
                   end

      candidates.filter_map do |rule|
        idx = rules.find_index { |r| r.equal?(rule) }
        idx && [rule, idx]
      end
    end

    # Fallback only, if #relevant_rules isn't available on this cancancan
    # version -- no alias-expansion awareness beyond :manage.
    def naive_relevant?(rule, action, model)
      (rule.subjects.include?(model) || rule.subjects.include?(:all)) &&
        (rule.actions.include?(action) || rule.actions.include?(:manage))
    end

    def source_snippet(location)
      return nil unless location

      { "file" => location.path, "line" => location.lineno, "text" => source_line(location) }
    end

    def source_line(location)
      File.readlines(location.path)[location.lineno - 1]&.strip
    rescue Errno::ENOENT, ArgumentError
      nil
    end

    def declared_models(abilities)
      models = Set.new
      abilities.each do |ability|
        ability.send(:rules).each do |rule|
          rule.subjects.each { |subject| models << subject unless subject == :all }
        end
      end
      models.to_a
    end

    def declared_actions(abilities)
      actions = Set.new(DEFAULT_ACTIONS)
      abilities.each do |ability|
        ability.send(:rules).each { |rule| rule.actions.each { |action| actions << action } }
      end
      actions.to_a
    end

    def model_name(model)
      model.respond_to?(:name) ? model.name : model.to_s
    end
  end
end
