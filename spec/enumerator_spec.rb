# frozen_string_literal: true

require "cancancan"

class TestDocument; end

class TestAbility
  include CanCan::Ability

  def initialize(user)
    if user.admin?
      can :manage, :all
    else
      can :read, TestDocument
      can :update, TestDocument, user_id: user.id
      cannot :destroy, TestDocument
    end
  end
end

class TestAbilityWithFlatCondition
  include CanCan::Ability

  def initialize(user)
    can :read, TestDocument, team_id: user.team_id
  end
end

class TestAbilityWithBlock
  include CanCan::Ability

  def initialize(_user)
    can(:update, TestDocument) { |doc| doc == :nope }
  end
end

class TestAbilityWithLoop
  include CanCan::Ability

  def initialize(_user)
    %i[read update].each { |action| can action, TestDocument }
  end
end

class TestReport; end

class TestAbilityWithMultiActionModel
  include CanCan::Ability

  def initialize(_user)
    can %i[read update], [TestDocument, TestReport]
  end
end

def test_role_stand_ins
  {
    "admin" => RubyAbilityGraph::RoleStandIn.new(admin?: true),
    "member" => RubyAbilityGraph::RoleStandIn.new(admin?: false, id: 42)
  }
end

def struct_result_for(results, role:, action:, model:)
  results.find { |r| r.role == role && r.action == action && r.model == model }
end

RSpec.describe RubyAbilityGraph::Enumerator do
  let(:role_stand_ins) { test_role_stand_ins }
  subject(:results) { described_class.call(ability_class: TestAbility, role_stand_ins: role_stand_ins) }

  it "resolves an unconditional grant" do
    expect(struct_result_for(results, role: "member", action: "read", model: "TestDocument").allowed).to be true
  end

  it "resolves an explicit denial over any implicit grant" do
    expect(struct_result_for(results, role: "member", action: "destroy", model: "TestDocument").allowed).to be false
  end

  it "resolves :manage, :all as a full grant for that role" do
    expect(struct_result_for(results, role: "admin", action: "destroy", model: "TestDocument").allowed).to be true
  end

  it "does not grant actions with no matching rule" do
    expect(struct_result_for(results, role: "member", action: "create", model: "TestDocument").allowed).to be false
  end

  it "returns a Result for every role x declared-model x declared-action combination" do
    expect(results).not_to be_empty
    expect(results).to all(be_a(RubyAbilityGraph::Enumerator::Result))
  end

  it "marks an unconditional grant as resolved with a nil condition" do
    result = struct_result_for(results, role: "member", action: "read", model: "TestDocument")
    expect(result.confidence).to eq("resolved")
    expect(result.condition).to be_nil
  end

  it "marks a flat hash condition as resolved with its structured condition" do
    stand_ins = { "member" => RubyAbilityGraph::RoleStandIn.new(team_id: 7) }
    scoped_results = described_class.call(ability_class: TestAbilityWithFlatCondition, role_stand_ins: stand_ins)
    result = struct_result_for(scoped_results, role: "member", action: "read", model: "TestDocument")
    expect(result.confidence).to eq("resolved")
    expect(result.condition).to eq(team_id: 7)
  end

  it "marks a block condition as unsupported, with a reason and source snippet" do
    stand_ins = { "member" => RubyAbilityGraph::RoleStandIn.new }
    scoped_results = described_class.call(ability_class: TestAbilityWithBlock, role_stand_ins: stand_ins)
    result = struct_result_for(scoped_results, role: "member", action: "update", model: "TestDocument")
    expect(result.confidence).to eq("unsupported")
    expect(result.reasons).to include("block_condition")
    expect(result.sources.first["text"]).to include("can(:update")
  end

  it "marks rules built in a loop as unsupported due to dynamic rule generation" do
    stand_ins = { "member" => RubyAbilityGraph::RoleStandIn.new }
    scoped_results = described_class.call(ability_class: TestAbilityWithLoop, role_stand_ins: stand_ins)
    result = struct_result_for(scoped_results, role: "member", action: "read", model: "TestDocument")
    expect(result.confidence).to eq("unsupported")
    expect(result.reasons).to include("dynamic_rule_generation")
  end

  it "resolves a single `can` call covering multiple actions and models (#1.4)" do
    stand_ins = { "member" => RubyAbilityGraph::RoleStandIn.new }
    scoped_results = described_class.call(ability_class: TestAbilityWithMultiActionModel, role_stand_ins: stand_ins)

    [%w[read TestDocument], %w[update TestDocument], %w[read TestReport], %w[update TestReport]].each do |action, model|
      result = struct_result_for(scoped_results, role: "member", action: action, model: model)
      expect(result.confidence).to eq("resolved")
      expect(result.allowed).to be true
    end
  end

  it "does not mistake ordinary role branching for dynamic rule generation" do
    %w[admin member].each do |role|
      result = struct_result_for(results, role: role, action: "read", model: "TestDocument")
      expect(result.reasons).not_to include("dynamic_rule_generation")
    end
  end
end
