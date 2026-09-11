# frozen_string_literal: true

require "json"

RSpec.describe RubyAbilityGraph::HtmlReport do
  let(:results) do
    [
      { "role" => "admin", "action" => "read", "model" => "Document", "allowed" => true,
        "confidence" => "resolved", "condition" => nil, "reasons" => [] },
      { "role" => "member", "action" => "read", "model" => "Document", "allowed" => true,
        "confidence" => "resolved", "condition" => { "team_id" => 7 }, "reasons" => [] },
      { "role" => "member", "action" => "update", "model" => "Document", "allowed" => true,
        "confidence" => "unsupported", "condition" => nil, "reasons" => ["block_condition"] },
      { "role" => "member", "action" => "destroy", "model" => "Document", "allowed" => false,
        "confidence" => "resolved", "condition" => nil, "reasons" => [] }
    ]
  end

  def embedded_data(html)
    match = html.match(/var DATA = (\{.*?\});/m)
    JSON.parse(match[1])
  end

  it "renders a self-contained HTML document with no external requests" do
    html = described_class.call(results: results)
    expect(html).to start_with("<!doctype html>")
    expect(html).not_to match(%r{https?://})
    expect(html).not_to include("<link ")
  end

  it "only embeds allowed rows -- denials aren't graph edges" do
    data = embedded_data(described_class.call(results: results))
    expect(data["rows"].size).to eq(3)
    expect(data["rows"].map { |r| r["action"] }).not_to include("destroy")
  end

  it "carries confidence and condition through per row" do
    data = embedded_data(described_class.call(results: results))
    row = data["rows"].find { |r| r["role"] == "member" && r["action"] == "read" }
    expect(row["confidence"]).to eq("resolved")
    expect(row["condition"]).to eq({ "team_id" => 7 })
  end

  it "computes coverage over all results, not just allowed ones" do
    data = embedded_data(described_class.call(results: results))
    expect(data["coverage"]).to eq({ "resolved" => 3, "total" => 4, "pct" => 75.0 })
  end

  it "leaves violationCount nil when no policy file was checked" do
    data = embedded_data(described_class.call(results: results))
    expect(data["violationCount"]).to be_nil
  end

  it "reports violationCount and flags matching rows when violations are given" do
    violations = [{ "role" => "member", "action" => "read", "model" => "Document" }]
    data = embedded_data(described_class.call(results: results, violations: violations))
    expect(data["violationCount"]).to eq(1)
    flagged = data["rows"].find { |r| r["role"] == "member" && r["action"] == "read" }
    expect(flagged["violation"]).to be true
    expect(data["rows"].find { |r| r["role"] == "admin" }["violation"]).to be false
  end

  it "reports violationCount of zero for a clean policy check" do
    data = embedded_data(described_class.call(results: results, violations: []))
    expect(data["violationCount"]).to eq(0)
  end

  it "escapes a literal </script> inside a condition so it can't close the inline script early" do
    tricky_results = [
      { "role" => "admin", "action" => "read", "model" => "Document", "allowed" => true,
        "confidence" => "resolved", "condition" => { "note" => "</script><script>alert(1)</script>" },
        "reasons" => [] }
    ]
    html = described_class.call(results: tricky_results)
    expect(html.scan("</script>").size).to eq(1) # only our own closing tag
    data = embedded_data(html)
    expect(data["rows"].first["condition"]["note"]).to eq("</script><script>alert(1)</script>")
  end
end
