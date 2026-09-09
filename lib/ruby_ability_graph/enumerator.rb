# frozen_string_literal: true

module RubyAbilityGraph
  # Runs a loaded Ability class's can? checks across every role x declared
  # action x declared model combination and returns the raw results.
  class Enumerator
    Result = Struct.new(:role, :action, :model, :allowed, keyword_init: true)
    DEFAULT_ACTIONS = %i[index show create update destroy manage read].freeze

    def self.call(ability_class:, role_stand_ins:)
      new(ability_class: ability_class, role_stand_ins: role_stand_ins).call
    end

    def initialize(ability_class:, role_stand_ins:)
      @ability_class = ability_class
      @role_stand_ins = role_stand_ins
    end

    def call
      abilities = @role_stand_ins.transform_values { |user| @ability_class.new(user) }
      models = declared_models(abilities.values)
      actions = declared_actions(abilities.values)

      build_results(abilities, models, actions)
    end

    private

    def build_results(abilities, models, actions)
      results = []
      abilities.each do |role, ability|
        models.each do |model|
          actions.each { |action| results << build_result(role, ability, model, action) }
        end
      end
      results
    end

    def build_result(role, ability, model, action)
      Result.new(
        role: role.to_s,
        action: action.to_s,
        model: model_name(model),
        allowed: ability.can?(action, model)
      )
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
