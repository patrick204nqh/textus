require "spec_helper"

Textus::CLI.verbs # trigger Runner.install! so the Gen* verb classes exist

RSpec.describe "restructure CLI verbs" do
  it "registers Group::Data with command_name 'data'" do
    expect(Textus::CLI::Group::Data.command_name).to eq("data")
  end

  it "registers the generated data mv verb under the data group" do
    expect(Textus::CLI::Verb::GenDataMv.command_name).to eq("mv")
    expect(Textus::CLI::Verb::GenDataMv.parent_group).to eq(Textus::CLI::Group::Data)
  end

  it "registers the generated rule lint verb under the rule group" do
    expect(Textus::CLI::Verb::GenRuleLint.command_name).to eq("lint")
    expect(Textus::CLI::Verb::GenRuleLint.parent_group).to eq(Textus::CLI::Group::Rule)
  end

  it "registers the generated key delete + delete-prefix verbs under the key group" do
    expect(Textus::CLI::Verb::GenKeyDelete.command_name).to eq("delete")
    expect(Textus::CLI::Verb::GenKeyDelete.parent_group).to eq(Textus::CLI::Group::Key)
    expect(Textus::CLI::Verb::GenKeyDeletePrefix.command_name).to eq("delete-prefix")
    expect(Textus::CLI::Verb::GenKeyDeletePrefix.parent_group).to eq(Textus::CLI::Group::Key)
  end

  it "registers the generated key mv + mv-prefix verbs under the key group" do
    expect(Textus::CLI::Verb::GenKeyMv.command_name).to eq("mv")
    expect(Textus::CLI::Verb::GenKeyMv.parent_group).to eq(Textus::CLI::Group::Key)
    expect(Textus::CLI::Verb::GenKeyMvPrefix.command_name).to eq("mv-prefix")
    expect(Textus::CLI::Verb::GenKeyMvPrefix.parent_group).to eq(Textus::CLI::Group::Key)
  end
end
