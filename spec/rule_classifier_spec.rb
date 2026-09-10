# frozen_string_literal: true

require "cancancan"

class ClassifierTestDocument
  def self.reflect_on_association(name)
    name == :project ? :fake_reflection : nil
  end
end

def rule_for(&)
  ability_class = Class.new { include CanCan::Ability }
  ability = ability_class.new
  ability.instance_eval(&)
  ability.send(:rules).last
end

RSpec.describe RubyAbilityGraph::RuleClassifier do
  def classify(rule)
    described_class.call(rule: rule, model: ClassifierTestDocument)
  end

  it "resolves an unconditional rule" do
    result = classify(rule_for { can :read, ClassifierTestDocument })
    expect(result.confidence).to eq("resolved")
    expect(result.condition).to be_nil
  end

  it "resolves a flat hash condition with scalar values" do
    rule = rule_for { can :read, ClassifierTestDocument, team_id: 1, archived: false }
    result = classify(rule)
    expect(result.confidence).to eq("resolved")
    expect(result.condition).to eq(team_id: 1, archived: false)
  end

  it "does not special-case tenant-shaped keys -- flat scalars resolve regardless of key name" do
    result = classify(rule_for { can :read, ClassifierTestDocument, tenant_id: 1 })
    expect(result.confidence).to eq("resolved")
  end

  it "flags a block condition as unsupported" do
    rule = rule_for { can(:update, ClassifierTestDocument) { |doc| doc == :nope } }
    result = classify(rule)
    expect(result.confidence).to eq("unsupported")
    expect(result.reason).to eq("block_condition")
  end

  it "flags a nested hash condition as association-chained" do
    rule = rule_for { can :read, ClassifierTestDocument, project: { team_id: 1 } }
    result = classify(rule)
    expect(result.confidence).to eq("unsupported")
    expect(result.reason).to eq("association_chained")
  end

  it "flags a flat key naming a real association as requiring traversal" do
    rule = rule_for { can :read, ClassifierTestDocument, project: 1 }
    result = classify(rule)
    expect(result.confidence).to eq("unsupported")
    expect(result.reason).to eq("requires_association_traversal")
  end

  it "flags an unrecognized condition value shape (e.g. a Range) as unsupported" do
    rule = rule_for { can :read, ClassifierTestDocument, age: 18..65 }
    result = classify(rule)
    expect(result.confidence).to eq("unsupported")
    expect(result.reason).to eq("unrecognized_condition_value")
  end
end
