# frozen_string_literal: true

require "json"

RSpec.describe RubyAbilityGraph::ScanPresenter do
  let(:results) do
    [{ "role" => "admin", "action" => "read", "model" => "Document", "allowed" => true,
       "confidence" => "resolved", "condition" => nil }]
  end

  def report(violations: [], unmatched: [])
    RubyAbilityGraph::PolicyChecker::Report.new(violations: violations, unmatched: unmatched)
  end

  describe "#render" do
    it "renders a table by default" do
      presenter = described_class.new(format: "table", results: results, policy_report: nil)
      expect(presenter.render).to match(/ROLE\s+ACTION\s+MODEL/)
    end

    it "renders versioned JSON with a results key" do
      presenter = described_class.new(format: "json", results: results, policy_report: nil)
      payload = JSON.parse(presenter.render)
      expect(payload["schema_version"]).to eq(1)
      expect(payload["results"]).to eq(results)
      expect(payload).not_to have_key("policy_violations")
    end

    it "includes policy_violations and policy_unmatched in JSON when a policy was checked" do
      presenter = described_class.new(format: "json", results: results, policy_report: report)
      payload = JSON.parse(presenter.render)
      expect(payload["policy_violations"]).to eq([])
      expect(payload["policy_unmatched"]).to eq([])
    end

    it "appends a policy section to the table" do
      violation = { "role" => "member", "action" => "read", "model" => "Document",
                    "allowed_roles" => ["admin"], "confidence" => "resolved", "condition" => nil }
      presenter = described_class.new(format: "table", results: results, policy_report: report(violations: [violation]))
      expect(presenter.render).to include("Policy violations (1):")
      expect(presenter.render).to include("member can read Document")
    end

    it "flags an unmatched policy distinctly from a clean check" do
      unmatched = { "model" => "Payment", "action" => "read", "allowed_roles" => ["admin"] }
      presenter = described_class.new(format: "table", results: results, policy_report: report(unmatched: [unmatched]))
      expect(presenter.render).to include("Policy entries with no matching scan result")
      expect(presenter.render).to include("Payment / read")
    end

    it "strips control characters from violation lines before printing" do
      violation = { "role" => "member\e[31m", "action" => "read", "model" => "Document",
                    "allowed_roles" => ["admin"], "confidence" => "resolved", "condition" => nil }
      presenter = described_class.new(format: "table", results: results, policy_report: report(violations: [violation]))
      expect(presenter.render).not_to include("\e")
    end
  end

  describe "#problems?" do
    it "is false when no policy file was given (nil policy_report)" do
      expect(described_class.new(format: "table", results: results, policy_report: nil).problems?).to be false
    end

    it "is false when the policy passed clean" do
      expect(described_class.new(format: "table", results: results, policy_report: report).problems?).to be false
    end

    it "is true when there's at least one violation" do
      violation = { "role" => "member", "action" => "read", "model" => "Document",
                    "allowed_roles" => ["admin"], "confidence" => "resolved", "condition" => nil }
      presenter = described_class.new(format: "table", results: results, policy_report: report(violations: [violation]))
      expect(presenter.problems?).to be true
    end

    it "is true when there's an unmatched policy, even with zero violations" do
      unmatched = { "model" => "Payment", "action" => "read", "allowed_roles" => ["admin"] }
      presenter = described_class.new(format: "table", results: results, policy_report: report(unmatched: [unmatched]))
      expect(presenter.problems?).to be true
    end
  end
end
