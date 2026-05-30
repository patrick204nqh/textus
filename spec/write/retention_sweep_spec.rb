require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Write::RetentionSweep do
  include_context "textus_store_fixture"

  def build_store(retention)
    FileUtils.mkdir_p(File.join(root, "zones", "review", "notes"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [accept, propose] }
        - { name: agent, can: [propose] }
      zones:
        - { name: review, kind: queue }
      entries:
        - { key: review.notes, path: review/notes, zone: review, schema: null, owner: agent:self, nested: true, kind: nested }
      rules:
        - match: review.**
          retention: #{retention}
    YAML
    leaf = File.join(root, "zones", "review", "notes", "old.md")
    File.write(leaf, "---\nname: old\n---\nbody\n")
    old = Time.now - (40 * 86_400)
    File.utime(old, old, leaf)
    [Textus::Store.new(root), leaf]
  end

  def sweep(store)
    described_class.new(
      container: Textus::Container.from_store(store),
      call: test_ctx(role: "human"),
    ).call
  end

  it "deletes a leaf past expire_after and lists it under expired" do
    store, leaf = build_store("{ expire_after: 30d }")
    result = sweep(store)
    expect(result["expired"]).to eq(["review.notes.old"])
    expect(result["archived"]).to eq([])
    expect(File.exist?(leaf)).to be(false)
    expect(result["ok"]).to be(true)
  end

  it "archives a leaf past archive_after into <root>/archive and removes the original" do
    store, leaf = build_store("{ archive_after: 30d }")
    result = sweep(store)
    expect(result["archived"]).to eq(["review.notes.old"])
    expect(result["expired"]).to eq([])
    expect(File.exist?(leaf)).to be(false)
    expect(File.exist?(File.join(root, "archive", "zones", "review", "notes", "old.md"))).to be(true)
  end
end
