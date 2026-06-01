require "spec_helper"

RSpec.describe "init scaffolds the feeds.machines snapshot" do
  around { |ex| Dir.mktmpdir { |d| Dir.chdir(d) { ex.run } } }

  before { Textus::Init.run(File.join(Dir.pwd, ".textus")) }

  it "drops the intake hook" do
    expect(File).to exist(".textus/hooks/machine_intake.rb")
  end

  it "declares a nested feeds.machines intake entry, tracked:false, in the feeds zone" do
    manifest = Textus::Manifest.load(File.join(Dir.pwd, ".textus"))
    entry = manifest.data.entries.find { |e| e.key == "feeds.machines" }
    expect(entry).not_to be_nil
    expect(entry.intake?).to be(true)
    expect(entry.nested?).to be(true)
    expect(entry.tracked?).to be(false)
    expect(entry.publish_to).to eq([]) # never published (sensitive)
    expect(entry.zone).to eq("feeds")
  end

  it "gitignores the whole nested subtree (and still the run subtree)" do
    ignore = File.read(".textus/.gitignore")
    expect(ignore).to include("#{Textus::Layout::RUN}/")
    expect(ignore).to include("zones/feeds/machines/")
  end
end
