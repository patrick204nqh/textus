require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Review + accept" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/network/org"))
    FileUtils.mkdir_p(File.join(root, "zones/review"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human, ai, script] }
        - { name: review, writable_by: [ai, human] }
      entries:
        - { key: working.network.org, path: working/network/org, zone: working, schema: null, owner: o, nested: true }
        - { key: review,             path: review,             zone: review, schema: null, owner: o, nested: true }
    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  it "AI writes a proposal, human accepts, target appears, proposal removed" do
    store.put("review.2026-05-19-add-bob",
              meta: {
                "name" => "2026-05-19-add-bob",
                "proposal" => { "target_key" => "working.network.org.bob", "action" => "put" },
                "frontmatter" => { "name" => "bob", "org" => "acme" },
              },
              body: "Proposed",
              as: "ai")

    res = store.accept("review.2026-05-19-add-bob", as: "human")
    expect(res["target_key"]).to eq("working.network.org.bob")
    expect(File.exist?(File.join(root, "zones/working/network/org/bob.md"))).to be true
    expect(File.exist?(File.join(root, "zones/review/2026-05-19-add-bob.md"))).to be false
  end

  it "rejects accept when not --as=human" do
    store.put("review.foo",
              meta: {
                "name" => "foo",
                "proposal" => { "target_key" => "working.network.org.x", "action" => "put" },
                "frontmatter" => { "name" => "x" },
              },
              body: "", as: "ai")
    expect { store.accept("review.foo", as: "ai") }
      .to raise_error(Textus::ProposalError, /human/)
  end
end
