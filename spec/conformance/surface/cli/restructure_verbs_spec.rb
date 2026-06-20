require "spec_helper"

Textus::Surface::CLI.verbs # trigger Runner.install! so the Gen* verb classes exist

RSpec.describe "restructure CLI verbs" do
  it "registers Group::Data with command_name 'data'" do
    expect(Textus::Surface::CLI::Group::Data.command_name).to eq("data")
  end

  it "registers the generated data mv verb under the data group" do
    expect(Textus::Surface::CLI::Verb::GenDataMv.command_name).to eq("mv")
    expect(Textus::Surface::CLI::Verb::GenDataMv.parent_group).to eq(Textus::Surface::CLI::Group::Data)
  end

  it "registers the generated rule lint verb under the rule group" do
    expect(Textus::Surface::CLI::Verb::GenRuleLint.command_name).to eq("lint")
    expect(Textus::Surface::CLI::Verb::GenRuleLint.parent_group).to eq(Textus::Surface::CLI::Group::Rule)
  end

  it "registers the generated key delete + delete-prefix verbs under the key group" do
    expect(Textus::Surface::CLI::Verb::GenKeyDelete.command_name).to eq("delete")
    expect(Textus::Surface::CLI::Verb::GenKeyDelete.parent_group).to eq(Textus::Surface::CLI::Group::Key)
    expect(Textus::Surface::CLI::Verb::GenKeyDeletePrefix.command_name).to eq("delete-prefix")
    expect(Textus::Surface::CLI::Verb::GenKeyDeletePrefix.parent_group).to eq(Textus::Surface::CLI::Group::Key)
  end

  it "registers the generated key mv + mv-prefix verbs under the key group" do
    expect(Textus::Surface::CLI::Verb::GenKeyMv.command_name).to eq("mv")
    expect(Textus::Surface::CLI::Verb::GenKeyMv.parent_group).to eq(Textus::Surface::CLI::Group::Key)
    expect(Textus::Surface::CLI::Verb::GenKeyMvPrefix.command_name).to eq("mv-prefix")
    expect(Textus::Surface::CLI::Verb::GenKeyMvPrefix.parent_group).to eq(Textus::Surface::CLI::Group::Key)
  end
end
