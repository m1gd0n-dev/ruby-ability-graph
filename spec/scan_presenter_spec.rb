# frozen_string_literal: true

require "json"

RSpec.describe RubyAbilityGraph::ScanPresenter do
  let(:results) do
    [{ "role" => "admin", "action" => "read", "model" => "Document", "allowed" => true,
       "confidence" => "resolved", "condition" => nil }]
  end

  describe "#render" do
    it "renders a table by default" do
      presenter = described_class.new(format: "table", results: results, violations: nil)
      expect(presenter.render).to match(/ROLE\s+ACTION\s+MODEL/)
    end

    it "renders versioned JSON with a results key" do
      presenter = described_class.new(format: "json", results: results, violations: nil)
      payload = JSON.parse(presenter.render)
      expect(payload["schema_version"]).to eq(1)
      expect(payload["results"]).to eq(results)
      expect(payload).not_to have_key("policy_violations")
    end

    it "includes policy_violations in JSON when violations were checked (even if empty)" do
      presenter = described_class.new(format: "json", results: results, violations: [])
      payload = JSON.parse(presenter.render)
      expect(payload["policy_violations"]).to eq([])
    end

    it "appends a policy section to the table" do
      violation = { "role" => "member", "action" => "read", "model" => "Document",
                    "allowed_roles" => ["admin"], "confidence" => "resolved", "condition" => nil }
      presenter = described_class.new(format: "table", results: results, violations: [violation])
      expect(presenter.render).to include("Policy violations (1):")
      expect(presenter.render).to include("member can read Document")
    end
  end

  describe "#violations?" do
    it "is false when no policy file was given (nil violations)" do
      expect(described_class.new(format: "table", results: results, violations: nil).violations?).to be false
    end

    it "is false when the policy passed clean (empty violations)" do
      expect(described_class.new(format: "table", results: results, violations: []).violations?).to be false
    end

    it "is true when there's at least one violation" do
      violation = { "role" => "member", "action" => "read", "model" => "Document",
                    "allowed_roles" => ["admin"], "confidence" => "resolved", "condition" => nil }
      expect(described_class.new(format: "table", results: results, violations: [violation]).violations?).to be true
    end
  end
end
