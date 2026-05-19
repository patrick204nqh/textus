require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Init do
  it "scaffolds a .textus/ from the personal profile" do
    tmp = Dir.mktmpdir
    root = File.join(tmp, ".textus")
    Textus::Init.run(root, profile: "personal")
    expect(File.exist?(File.join(root, "manifest.yaml"))).to be true
    expect(File.directory?(File.join(root, "schemas"))).to be true
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end

  it "raises on unknown profile" do
    tmp = Dir.mktmpdir
    expect { Textus::Init.run(File.join(tmp, ".textus"), profile: "no-such") }
      .to raise_error(Textus::UsageError)
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end
end
