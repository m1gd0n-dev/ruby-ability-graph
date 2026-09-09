# frozen_string_literal: true

RSpec.describe RubyAbilityGraph::Inspector do
  it "lists every method called on `user`, sorted and deduped" do
    ability_file = fixture_path("toy_app", "app/models/ability.rb")
    result = described_class.new(ability_file: ability_file).call

    expect(result.method_names).to eq(%w[admin? id])
    expect(result.warning).to be_nil
  end

  it "warns, but still reports calls, when #initialize contains a block/proc" do
    ability_file = fixture_path("block_body_app", "app/models/ability.rb")
    result = described_class.new(ability_file: ability_file).call

    expect(result.method_names).to eq(%w[admin? team_ids])
    expect(result.warning).to match(/block or proc/)
  end
end

RSpec.describe RubyAbilityGraph::Inspector, "with an unusable ability file" do
  it "raises InspectionError for a missing file" do
    inspector = described_class.new(ability_file: fixture_path("toy_app", "app/models/nope.rb"))
    expect { inspector.call }.to raise_error(described_class::InspectionError, /No such file/)
  end

  it "raises InspectionError when the named class isn't found" do
    ability_file = fixture_path("toy_app", "app/models/ability.rb")
    inspector = described_class.new(ability_file: ability_file, ability_class_name: "NotAbility")
    expect { inspector.call }.to raise_error(described_class::InspectionError, /Could not find `class NotAbility`/)
  end
end

RSpec.describe RubyAbilityGraph::Inspector, "with an ability file it can't analyze" do
  it "raises InspectionError when #initialize takes no parameters" do
    Tempfile.create(["ability", ".rb"]) do |file|
      file.write("class Ability\n  def initialize; end\nend\n")
      file.flush

      inspector = described_class.new(ability_file: file.path)
      expect { inspector.call }.to raise_error(described_class::InspectionError, /takes no parameters/)
    end
  end

  it "raises InspectionError when #initialize itself is missing" do
    Tempfile.create(["ability", ".rb"]) do |file|
      file.write("class Ability\nend\n")
      file.flush

      inspector = described_class.new(ability_file: file.path)
      expect { inspector.call }.to raise_error(described_class::InspectionError, /initialize not found/)
    end
  end
end
