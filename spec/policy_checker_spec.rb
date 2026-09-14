# frozen_string_literal: true

RSpec.describe RubyAbilityGraph::PolicyChecker do
  let(:results) do
    [
      { "role" => "admin", "action" => "read", "model" => "Document", "allowed" => true,
        "confidence" => "resolved", "condition" => nil },
      { "role" => "member", "action" => "read", "model" => "Document", "allowed" => true,
        "confidence" => "resolved", "condition" => { "team_id" => 7 } },
      { "role" => "member", "action" => "destroy", "model" => "Document", "allowed" => false,
        "confidence" => "resolved", "condition" => nil }
    ]
  end

  it "flags a role that is allowed but not in allowed_roles" do
    policies = [{ "model" => "Document", "action" => "read", "allowed_roles" => ["admin"] }]
    report = described_class.call(policies: policies, results: results)

    expect(report.violations.size).to eq(1)
    expect(report.violations.first).to include("role" => "member", "action" => "read", "model" => "Document")
    expect(report.unmatched).to be_empty
  end

  it "does not flag a role that is allowed and in allowed_roles" do
    policies = [{ "model" => "Document", "action" => "read", "allowed_roles" => %w[admin member] }]
    expect(described_class.call(policies: policies, results: results).violations).to be_empty
  end

  it "does not flag a role that isn't actually allowed, even if absent from allowed_roles" do
    policies = [{ "model" => "Document", "action" => "destroy", "allowed_roles" => ["admin"] }]
    expect(described_class.call(policies: policies, results: results).violations).to be_empty
  end

  it "reports a policy with no matching results as unmatched, not clean" do
    policies = [{ "model" => "Report", "action" => "read", "allowed_roles" => ["admin"] }]
    report = described_class.call(policies: policies, results: results)

    expect(report.violations).to be_empty
    expect(report.unmatched).to eq(policies)
  end

  it "handles multiple policies independently" do
    policies = [
      { "model" => "Document", "action" => "read", "allowed_roles" => ["admin"] },
      { "model" => "Document", "action" => "destroy", "allowed_roles" => ["admin"] }
    ]
    report = described_class.call(policies: policies, results: results)
    expect(report.violations.map { |v| v["action"] }).to eq(["read"])
  end
end
