require "spec_helper"

Textus::Surfaces::CLI.verbs # trigger Runner.install! so the Gen* verb classes exist

RSpec.describe "restructure CLI verbs" do
  it "registers Group::Data with command_name 'data'" do
    expect(Textus::Surfaces::CLI::Group::Data.command_name).to eq("data")
  end

  it "registers the generated data mv verb under the data group" do
    expect(Textus::Surfaces::CLI::Verb::GenDataMv.command_name).to eq("mv")
    expect(Textus::Surfaces::CLI::Verb::GenDataMv.parent_group).to eq(Textus::Surfaces::CLI::Group::Data)
  end

  it "registers the generated rule lint verb under the rule group" do
    expect(Textus::Surfaces::CLI::Verb::GenRuleLint.command_name).to eq("lint")
    expect(Textus::Surfaces::CLI::Verb::GenRuleLint.parent_group).to eq(Textus::Surfaces::CLI::Group::Rule)
  end

  it "registers the generated key delete + delete-prefix verbs under the key group" do
    expect(Textus::Surfaces::CLI::Verb::GenKeyDelete.command_name).to eq("delete")
    expect(Textus::Surfaces::CLI::Verb::GenKeyDelete.parent_group).to eq(Textus::Surfaces::CLI::Group::Key)
    expect(Textus::Surfaces::CLI::Verb::GenKeyDeletePrefix.command_name).to eq("delete-prefix")
    expect(Textus::Surfaces::CLI::Verb::GenKeyDeletePrefix.parent_group).to eq(Textus::Surfaces::CLI::Group::Key)
  end

  it "registers the generated key mv + mv-prefix verbs under the key group" do
    expect(Textus::Surfaces::CLI::Verb::GenKeyMv.command_name).to eq("mv")
    expect(Textus::Surfaces::CLI::Verb::GenKeyMv.parent_group).to eq(Textus::Surfaces::CLI::Group::Key)
    expect(Textus::Surfaces::CLI::Verb::GenKeyMvPrefix.command_name).to eq("mv-prefix")
    expect(Textus::Surfaces::CLI::Verb::GenKeyMvPrefix.parent_group).to eq(Textus::Surfaces::CLI::Group::Key)
  end
end
