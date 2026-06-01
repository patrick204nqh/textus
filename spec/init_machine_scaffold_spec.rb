require "spec_helper"

RSpec.describe "init scaffolds the feeds.machine snapshot" do
  around { |ex| Dir.mktmpdir { |d| Dir.chdir(d) { ex.run } } }

  before { Textus::Init.run(File.join(Dir.pwd, ".textus")) }

  it "drops the intake hook" do
    expect(File).to exist(".textus/hooks/machine_intake.rb")
  end

  it "declares a feeds.machine intake entry, tracked:false, retrievable by key" do
    manifest = Textus::Manifest.load(File.join(Dir.pwd, ".textus"))
    entry = manifest.data.entries.find { |e| e.key == "feeds.machine" }
    expect(entry).not_to be_nil
    expect(entry.intake?).to be(true)
    expect(entry.tracked?).to be(false)
    expect(entry.publish_to).to eq([]) # never published (sensitive)
    # normal feeds zone path → addressable via the protocol
    target = Textus::Key::Path.resolve(manifest.data, entry)
    expect(target).to include(File.join("zones", "feeds"))
  end

  it "gitignores the tracked:false entry (and still the run subtree)" do
    ignore = File.read(".textus/.gitignore")
    expect(ignore).to include("#{Textus::Layout::RUN}/")
    expect(ignore).to include("zones/feeds/machine")
  end
end
