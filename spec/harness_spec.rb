# frozen_string_literal: true

require "yaml"
require "tempfile"

RSpec.describe RubyAbilityGraph::Harness do
  let(:app_path) { fixture_path("toy_app") }
  let(:roles) { roles_for(app_path) }

  subject(:results) { described_class.new(app_path: app_path, roles: roles).run }

  it "runs the toy app's Ability class end-to-end and returns raw results" do
    expect(results).not_to be_empty
    expect(result_for(results, role: "member", action: "read", model: "Document")["allowed"]).to be true
    expect(result_for(results, role: "member", action: "destroy", model: "Document")["allowed"]).to be false
    expect(result_for(results, role: "admin", action: "destroy", model: "Document")["allowed"]).to be true
  end

  it "raises a Harness::LoadError with the target app's own error output when loading fails" do
    broken = described_class.new(app_path: app_path, roles: roles, ability_file: "nope.rb")
    expect { broken.run }.to raise_error(described_class::LoadError, /nope\.rb/)
  end
end

RSpec.describe RubyAbilityGraph::Harness, "with ruby_bin: (cross-Ruby-version target support)" do
  let(:app_path) { fixture_path("toy_app") }
  let(:roles) { roles_for(app_path) }
  let(:fake_ruby_bin) { fixture_path("fake_ruby_bin", "fake_ruby") }

  it "invokes the given ruby_bin instead of the bare \"ruby\" command" do
    Tempfile.create("ruby_ability_graph_fake_ruby_marker") do |marker|
      with_env("FAKE_RUBY_BIN_MARKER" => marker.path) do
        described_class.new(app_path: app_path, roles: roles, ruby_bin: fake_ruby_bin).run
      end

      expect(File.read(marker.path)).to eq("1")
    end
  end

  it "still returns correct results once the custom ruby_bin execs the real interpreter" do
    results = with_env("FAKE_RUBY_BIN_MARKER" => nil) do
      described_class.new(app_path: app_path, roles: roles, ruby_bin: fake_ruby_bin).run
    end

    expect(results).not_to be_empty
    expect(result_for(results, role: "member", action: "read", model: "Document")["allowed"]).to be true
    expect(result_for(results, role: "admin", action: "destroy", model: "Document")["allowed"]).to be true
  end
end

RSpec.describe RubyAbilityGraph::Harness, "against an Ability class that references an unloaded model (#2)" do
  let(:app_path) { fixture_path("unrequired_app") }
  let(:document_path) { File.join(app_path, "app/models/document.rb") }
  let(:roles) { roles_for(app_path) }

  it "fails with the referenced constant undefined when nothing preloads it" do
    harness = described_class.new(app_path: app_path, roles: roles)
    expect { harness.run }.to raise_error(described_class::LoadError, /uninitialized constant/)
  end

  it "resolves the Ability class once the referenced model is preloaded via requires:" do
    harness = described_class.new(app_path: app_path, roles: roles, requires: ["app/models/document.rb"])
    results = harness.run

    expect(results).not_to be_empty
    expect(result_for(results, role: "member", action: "read", model: "Document")["allowed"]).to be true
    expect(result_for(results, role: "member", action: "destroy", model: "Document")["allowed"]).to be false
    expect(result_for(results, role: "admin", action: "destroy", model: "Document")["allowed"]).to be true
  end

  it "accepts an absolute path for requires: too" do
    harness = described_class.new(app_path: app_path, roles: roles, requires: [document_path])
    expect { harness.run }.not_to raise_error
  end
end

RSpec.describe RubyAbilityGraph::Harness, "against a target with its own Gemfile" do
  let(:app_path) { fixture_path("bundled_app") }
  let(:roles) { roles_for(app_path) }

  before(:context) do
    Bundler.with_unbundled_env do
      system("bundle install --quiet", chdir: fixture_path("bundled_app"), exception: true)
    end
  end

  subject(:results) { described_class.new(app_path: app_path, roles: roles).run }

  it "runs the toy app's Ability class end-to-end via `bundle exec`" do
    expect(results).not_to be_empty
    expect(result_for(results, role: "member", action: "read", model: "Document")["allowed"]).to be true
    expect(result_for(results, role: "member", action: "destroy", model: "Document")["allowed"]).to be false
    expect(result_for(results, role: "admin", action: "destroy", model: "Document")["allowed"]).to be true
  end
end

RSpec.describe RubyAbilityGraph::Harness, "with rails_boot: (#3)" do
  let(:app_path) { fixture_path("rails_shaped_app") }
  let(:roles) { roles_for(app_path) }

  it "resolves the Ability class via bin/rails runner with the default rails_env (test)" do
    harness = described_class.new(app_path: app_path, roles: roles, rails_boot: true)
    results = harness.run

    expect(results).not_to be_empty
    expect(result_for(results, role: "member", action: "read", model: "Document")["allowed"]).to be true
    expect(result_for(results, role: "member", action: "destroy", model: "Document")["allowed"]).to be false
    expect(result_for(results, role: "admin", action: "destroy", model: "Document")["allowed"]).to be true
  end

  it "threads a custom rails_env: through to the bin/rails runner subprocess" do
    harness = described_class.new(app_path: app_path, roles: roles, rails_boot: true, rails_env: "staging_test")
    expect { harness.run }.not_to raise_error
  end
end

RSpec.describe RubyAbilityGraph::Harness, "with rails_boot: and invalid configuration (#3)" do
  let(:app_path) { fixture_path("rails_shaped_app") }
  let(:roles) { roles_for(app_path) }

  it "raises a LoadError naming the missing rails_env when it isn't one the target accepts" do
    harness = described_class.new(app_path: app_path, roles: roles, rails_boot: true, rails_env: "production")
    expect { harness.run }.to raise_error(described_class::LoadError, /RAILS_ENV not set/)
  end

  it "raises a clear LoadError when rails_boot: is set against an app with no bin/rails" do
    harness = described_class.new(app_path: fixture_path("toy_app"), roles: roles, rails_boot: true)
    expect { harness.run }.to raise_error(described_class::LoadError, %r{no bin/rails found})
  end

  it "raises an ArgumentError when combined with a non-empty requires:" do
    expect do
      described_class.new(app_path: app_path, roles: roles, rails_boot: true, requires: ["app/models/document.rb"])
    end.to raise_error(ArgumentError, /not compatible with rails_boot/)
  end
end
