# frozen_string_literal: true

RSpec.describe RubyAbilityGraph::TableFormatter do
  let(:results) do
    [
      { "role" => "admin", "action" => "read", "model" => "Document", "allowed" => true,
        "confidence" => "resolved", "condition" => nil },
      { "role" => "member", "action" => "read", "model" => "Document", "allowed" => true,
        "confidence" => "resolved", "condition" => { "team_id" => 7 } },
      { "role" => "member", "action" => "update", "model" => "Document", "allowed" => true,
        "confidence" => "unsupported", "condition" => nil }
    ]
  end

  subject(:table) { described_class.call(results) }

  it "includes a header row" do
    expect(table).to match(/ROLE\s+ACTION\s+MODEL\s+ALLOWED\s+CONFIDENCE\s+CONDITION/)
  end

  it "renders a row per result, condition rendered as-is and nil as a dash" do
    expect(table).to match(/admin\s+read\s+Document\s+true\s+resolved\s+-/)
    expect(table).to include('{"team_id"=>7}')
  end

  it "sorts rows by role, then model, then action" do
    admin_line = table.lines.find { |l| l.start_with?("admin") }
    member_lines = table.lines.select { |l| l.start_with?("member") }
    expect(table.index(admin_line)).to be < table.index(member_lines.first)
    expect(member_lines.first).to match(/\bread\b/)
    expect(member_lines.last).to match(/\bupdate\b/)
  end

  it "summarizes resolved vs total coverage" do
    expect(table).to include("2/3 resolved (66.7%)")
  end

  it "handles an empty result set without dividing by zero" do
    expect(described_class.call([])).to include("0/0 resolved (0%)")
  end
end
