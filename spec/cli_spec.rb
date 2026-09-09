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
    end.to output(/"raw_results"/).to_stdout
  end
end
