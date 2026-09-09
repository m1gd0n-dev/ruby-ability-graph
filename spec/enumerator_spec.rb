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
end
