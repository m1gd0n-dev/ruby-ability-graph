# frozen_string_literal: true

RSpec.describe RubyAbilityGraph::CLI do
  let(:app_path) { fixture_path("toy_app") }

  it "aborts with a clear message when --rails-env is passed without --rails-boot" do
    expect do
      described_class.start(["scan", app_path, "--rails-env", "test"])
    end.to output(/--rails-env only applies with --rails-boot/).to_stderr.and raise_error(SystemExit)
  end

  it "aborts with a clear message when --require is combined with --rails-boot" do
    expect do
      described_class.start(["scan", app_path, "--rails-boot", "--require", "app/models/document.rb"])
    end.to output(/--require is not compatible with --rails-boot/).to_stderr.and raise_error(SystemExit)
  end

  it "threads --ruby-bin through to Harness, running the analysis subprocess under it" do
    fake_ruby_bin = fixture_path("fake_ruby_bin", "fake_ruby")

    expect do
      described_class.start(["scan", app_path, "--ruby-bin", fake_ruby_bin])
    end.to output(/resolved \(/).to_stdout
  end

  it "defaults to a human-readable table" do
    expect do
      described_class.start(["scan", app_path])
    end.to output(/ROLE\s+ACTION\s+MODEL\s+ALLOWED\s+CONFIDENCE\s+CONDITION/).to_stdout
  end

  it "prints the versioned JSON schema with --format json" do
    expect do
      described_class.start(["scan", app_path, "--format", "json"])
    end.to output(/"schema_version": 1.*"results"/m).to_stdout
  end

  it "rejects an unrecognized --format value" do
    expect do
      described_class.start(["scan", app_path, "--format", "yaml"])
    end.to raise_error(OptionParser::InvalidArgument)
  end

  context "with --policy-file" do
    it "reports no violations, without exiting, when the policy holds" do
      expect do
        described_class.start(["scan", app_path, "--policy-file", "policy_ok.yml"])
      end.to output(/no violations/).to_stdout
    end

    it "flags a role that can do more than the policy allows, and exits non-zero" do
      expect do
        described_class.start(["scan", app_path, "--policy-file", "policy_violation.yml"])
      end.to output(/Policy violations \(1\):.*member can read Document/m).to_stdout.and raise_error(SystemExit) { |e|
        expect(e.status).to eq(1)
      }
    end

    it "includes policy_violations in JSON output" do
      expect do
        described_class.start(["scan", app_path, "--policy-file", "policy_violation.yml", "--format", "json"])
      end.to output(/"policy_violations"/).to_stdout.and raise_error(SystemExit)
    end
  end
end
