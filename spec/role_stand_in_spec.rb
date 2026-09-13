# frozen_string_literal: true

RSpec.describe RubyAbilityGraph::RoleStandIn do
  it "answers a flat attribute" do
    stand_in = described_class.new("id" => 1, "admin?" => true)
    expect(stand_in.id).to eq(1)
    expect(stand_in.admin?).to be true
  end

  it "raises NoMethodError for an attribute the roles file didn't provide" do
    stand_in = described_class.new("id" => 1)
    expect { stand_in.group_ids }.to raise_error(NoMethodError)
  end

  it "reports respond_to? accurately for provided and missing attributes" do
    stand_in = described_class.new("id" => 1)
    expect(stand_in.respond_to?(:id)).to be true
    expect(stand_in.respond_to?(:group_ids)).to be false
  end

  it "wraps a nested Hash attribute as another stand-in, not a plain Hash" do
    # Real-world pattern found dogfooding consuldemocracy: Abilities::Valuator
    # calls `user.valuator.can_edit_dossier?` -- a method call on an
    # *associated* object, not a flat attribute on user itself.
    stand_in = described_class.new("valuator" => { "can_edit_dossier?" => true, "assigned_investment_ids" => [1, 2] })
    expect(stand_in.valuator).to be_a(described_class)
    expect(stand_in.valuator.can_edit_dossier?).to be true
    expect(stand_in.valuator.assigned_investment_ids).to eq([1, 2])
  end

  it "wraps each Hash element of an Array attribute (has-many-shaped stand-ins)" do
    stand_in = described_class.new("assignments" => [{ "status" => "done" }, { "status" => "pending" }])
    expect(stand_in.assignments).to all(be_a(described_class))
    expect(stand_in.assignments.map(&:status)).to eq(%w[done pending])
  end

  it "leaves non-Hash Array elements alone" do
    stand_in = described_class.new("group_ids" => [1, 2, 3])
    expect(stand_in.group_ids).to eq([1, 2, 3])
  end
end
