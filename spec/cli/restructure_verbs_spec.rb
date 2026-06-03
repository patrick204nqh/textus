require "spec_helper"

RSpec.describe "restructure CLI verbs" do
  it "registers Group::Zone with command_name 'zone'" do
    expect(Textus::CLI::Group::Zone.command_name).to eq("zone")
  end

  it "registers the generated zone mv verb under the zone group" do
    expect(Textus::CLI::Verb::GenZoneMv.command_name).to eq("mv")
    expect(Textus::CLI::Verb::GenZoneMv.parent_group).to eq(Textus::CLI::Group::Zone)
  end

  it "registers the generated rule lint verb under the rule group" do
    expect(Textus::CLI::Verb::GenRuleLint.command_name).to eq("lint")
    expect(Textus::CLI::Verb::GenRuleLint.parent_group).to eq(Textus::CLI::Group::Rule)
  end

  it "registers the generated key delete + delete-prefix verbs under the key group" do
    expect(Textus::CLI::Verb::GenDelete.command_name).to eq("delete")
    expect(Textus::CLI::Verb::GenDelete.parent_group).to eq(Textus::CLI::Group::Key)
    expect(Textus::CLI::Verb::GenKeyDeletePrefix.command_name).to eq("delete-prefix")
    expect(Textus::CLI::Verb::GenKeyDeletePrefix.parent_group).to eq(Textus::CLI::Group::Key)
  end

  it "registers the generated migrate verb as a top-level verb" do
    expect(Textus::CLI::Verb::GenMigrate.command_name).to eq("migrate")
    expect(Textus::CLI::Verb::GenMigrate.parent_group).to be_nil
  end

  it "Verb::Mv exposes a --prefix flag" do
    expect(Textus::CLI::Verb::Mv.options.map(&:first)).to include(:prefix)
  end
end
