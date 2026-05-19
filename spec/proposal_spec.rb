require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Pending + accept" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/network/org"))
    FileUtils.mkdir_p(File.join(root, "zones/pending"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: working, writable_by: [human, ai, script] }
        - { name: pending, writable_by: [ai, human] }
      entries:
        - { key: working.network.org, path: working/network/org, zone: working, schema: null, owner: o, nested: true }
        - { key: pending,             path: pending,             zone: pending, schema: null, owner: o, nested: true }
    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  it "AI writes a proposal, human accepts, target appears, proposal removed" do
    store.put("pending.2026-05-19-add-bob",
              frontmatter: {
                "name" => "2026-05-19-add-bob",
                "proposal" => { "target_key" => "working.network.org.bob", "action" => "put" },
                "frontmatter" => { "name" => "bob", "org" => "acme" },
              },
              body: "Proposed",
              as: "ai")

    res = store.accept("pending.2026-05-19-add-bob", as: "human")
    expect(res["target_key"]).to eq("working.network.org.bob")
    expect(File.exist?(File.join(root, "zones/working/network/org/bob.md"))).to be true
    expect(File.exist?(File.join(root, "zones/pending/2026-05-19-add-bob.md"))).to be false
  end

  it "rejects accept when not --as=human" do
    store.put("pending.foo",
              frontmatter: {
                "name" => "foo",
                "proposal" => { "target_key" => "working.network.org.x", "action" => "put" },
                "frontmatter" => { "name" => "x" },
              },
              body: "", as: "ai")
    expect { store.accept("pending.foo", as: "ai") }
      .to raise_error(Textus::ProposalError, /human/)
  end
end
