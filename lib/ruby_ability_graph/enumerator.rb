# frozen_string_literal: true

require_relative "rule_classifier"

module RubyAbilityGraph
  # Runs a loaded Ability class's can? checks across every role x declared
  # action x declared model combination, classifying each result as
  # resolved/unsupported (via RuleClassifier) rather than returning a bare
  # boolean.
  class Enumerator
    Result = Struct.new(
      :role, :action, :model, :allowed, :confidence, :condition, :reasons, :sources, keyword_init: true
    )
    DEFAULT_ACTIONS = %i[index show create update destroy manage read].freeze

    # Records where each rule was truly declared, by wrapping CanCan::Ability's
    # own rule-append point -- prepended onto the CanCan::Ability MODULE
    # itself (not a specific Ability class), so it applies uniformly to every
    # class that includes it. That matters because larger apps commonly split
    # authorization across several classes merged together (e.g. a top-level
    # `Ability` doing `merge Abilities::Administrator.new(user)`, itself
    # merging further sub-abilities -- found dogfooding consuldemocracy).
    # Prepending only the top-level class would mean a rule declared inside
    # a merged-in class gets *re-added* during merge, and naive recording
    # would attribute it to the merge call site, not its real declaration --
    # every rule sharing that merge line would then look like it fired more
    # than once, indistinguishable from a genuine loop-built rule.
    #
    # The source is stashed directly on the rule object (set once, at first
    # sighting) rather than in an array indexed by position, so it survives
    # being re-added to another ability's own @rules during merge.
    module RuleSourceRecording
      # Larger apps commonly split `can`/`cannot` declarations out of Ability
      # itself via a plain forwarding method -- Solidus's whole
      # PermissionSets framework works this way (`delegate :can, :cannot,
      # :user, to: :ability` in every permission set's base class, found
      # dogfooding solidus). A delegate-generated method's OWN recorded
      # file/line is wherever `delegate :can, ...` itself was written, not
      # the permission set subclass that actually calls it -- so the first
      # non-cancancan frame there is a dead end, and every rule declared
      # through that same delegate line collapses to one identical,
      # unhelpful source pointer. Skipping frames whose method name is
      # itself can/cannot (regardless of whether the forwarding was done via
      # `delegate`, `alias`, or a hand-written wrapper) walks past that and
      # lands on the real call site instead.
      #
      # Location#label isn't just the bare method name -- on this Ruby
      # version it's qualified as "PermBase#can" (confirmed empirically;
      # comparing against a bare "can"/"cannot" silently never matched and
      # let the very bug this is meant to fix through). Match on either form.
      FORWARDING_METHOD_NAME = /(\A|#)(can|cannot)\z/

      def add_rule(rule)
        unless rule.instance_variable_defined?(:@rag_source)
          location = caller_locations.find do |loc|
            !loc.path.include?("cancancan") && !FORWARDING_METHOD_NAME.match?(loc.label)
          end
          rule.instance_variable_set(:@rag_source, location)
        end
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

    # Prepended onto the CanCan::Ability module -- see RuleSourceRecording --
    # so this only ever needs to run once, regardless of which Ability-like
    # class we're pointed at. No-op entirely if the target's cancancan
    # version doesn't define #add_rule -- source/dynamic-generation data is
    # simply unavailable then, not fatal.
    def ensure_source_recording!
      return if CanCan::Ability.ancestors.include?(RuleSourceRecording)
      return unless CanCan::Ability.method_defined?(:add_rule) || CanCan::Ability.private_method_defined?(:add_rule)

      CanCan::Ability.prepend(RuleSourceRecording)
    end

    def build_results(abilities, models, actions)
      results = []
      abilities.each do |role, ability|
        dynamic_rules = dynamic_rule_set(ability.send(:rules))
        models.each do |model|
          actions.each { |action| results << build_result(role, ability, model, action, dynamic_rules) }
        end
      end
      results
    end

    # A rule counts as dynamically generated only if it shares its true
    # declaration line with at least one OTHER rule from this same
    # instantiation whose subjects/actions/conditions actually differ -- e.g.
    # Fat Free CRM's `permissions.each { |p| can :manage, ..., id: p.asset_id }`,
    # where every iteration produces a different condition. Same line but
    # every rule otherwise identical is what a merged-in class reached via
    # more than one path looks like (see RuleSourceRecording) -- that's
    # static duplication, not a loop, and shouldn't taint an otherwise
    # perfectly resolvable rule.
    def dynamic_rule_set(rules)
      rules.group_by { |rule| location_key(rule_source(rule)) }
           .reject { |key, _| key.nil? }
           .values
           .select { |group| group.size > 1 && varies?(group) }
           .flatten
           .to_set
    end

    # Thread::Backtrace::Location has no value equality of its own -- two
    # separate calls to caller_locations, even for the exact same physical
    # line, return objects that are neither `==` nor `eql?` to each other
    # (confirmed empirically). Grouping by the raw Location silently never
    # merged anything, so this whole dynamic-vs-static check was a no-op
    # from the moment it shipped. [path, lineno] is a plain, hashable-by-
    # value key that actually collapses same-site rules.
    def location_key(location)
      return nil unless location

      [location.path, location.lineno]
    end

    def varies?(group)
      group.map { |rule| [rule.subjects, rule.actions, rule.conditions] }.uniq.size > 1
    end

    def build_result(role, ability, model, action, dynamic_rules)
      contributing = relevant_rules(ability, action, model)
      classifications = contributing.map { |rule| classify(rule, model, dynamic_rules) }

      Result.new(
        role: role.to_s,
        action: action.to_s,
        model: model_name(model),
        allowed: ability.can?(action, model),
        **verdict(classifications)
      )
    end

    def classify(rule, model, dynamic_rules)
      return dynamic_classification(rule) if dynamic_rules.include?(rule)

      classification = RuleClassifier.call(rule: rule, model: model)
      classification.source = source_snippet(rule_source(rule)) if classification.confidence == "unsupported"
      classification
    end

    def dynamic_classification(rule)
      RuleClassifier::Classification.new(
        confidence: "unsupported",
        condition: nil,
        reason: "dynamic_rule_generation",
        source: source_snippet(rule_source(rule))
      )
    end

    # Every rule contributing to this (action, model) pair must itself be
    # resolved for the combined result to be resolved -- we trust can? for
    # the boolean, not our own guess at resolution order.
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
      condition = conditions.size <= 1 ? conditions.first : conditions
      { confidence: "resolved", condition: condition, reasons: [], sources: [] }
    end

    # Rules whose action/subject match this (action, model) pair, regardless
    # of whether their condition currently evaluates true or false -- any one
    # of them being unsupported taints the whole pair (see #verdict).
    def relevant_rules(ability, action, model)
      if ability.respond_to?(:relevant_rules, true)
        ability.send(:relevant_rules, action, model)
      else
        ability.send(:rules).select { |r| naive_relevant?(r, action, model) }
      end
    end

    # Fallback only, if #relevant_rules isn't available on this cancancan
    # version -- no alias-expansion awareness beyond :manage.
    def naive_relevant?(rule, action, model)
      (rule.subjects.include?(model) || rule.subjects.include?(:all)) &&
        (rule.actions.include?(action) || rule.actions.include?(:manage))
    end

    def rule_source(rule)
      rule.instance_variable_get(:@rag_source) if rule.instance_variable_defined?(:@rag_source)
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
