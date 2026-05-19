require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::StoreView do
  let(:tmp) { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
    File.write(File.join(root, "zones/working/x.md"), "---\nname: x\n---\nhi\n")
  end

  after { FileUtils.remove_entry(tmp) }

  it "exposes read methods" do
    view = described_class.new(Textus::Store.new(root))
    expect(view.get("working.x")["body"]).to eq("hi\n")
    expect(view.list).to be_an(Array)
    expect(view.where("working.x")["path"]).to end_with("working/x.md")
  end

  it "raises on write attempts" do
    view = described_class.new(Textus::Store.new(root))
    expect { view.put("working.x", frontmatter: {}, body: "") }
      .to raise_error(Textus::UsageError, /read-only/)
    expect { view.delete("working.x") }
      .to raise_error(Textus::UsageError, /read-only/)
  end
end
