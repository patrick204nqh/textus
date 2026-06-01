require "spec_helper"

RSpec.describe Textus::Write::RetentionSweep do
  include_context "textus_store_fixture"

  def build_store(retention)
    s = store_from_manifest(root, zones: %w[proposals], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose] }
      zones:
        - { name: proposals, kind: queue }
      entries:
        - { key: proposals.notes, path: proposals/notes, zone: proposals, owner: agent:self, kind: nested }
      rules:
        - match: proposals.**
          retention: #{retention}
    YAML
    FileUtils.mkdir_p(File.join(root, "zones", "proposals", "notes"))
    leaf = File.join(root, "zones", "proposals", "notes", "old.md")
    File.write(leaf, "---\nname: old\n---\nbody\n")
    old = Time.now - (40 * 86_400)
    File.utime(old, old, leaf)
    [s, leaf]
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
    expect(result["expired"]).to eq(["proposals.notes.old"])
    expect(result["archived"]).to eq([])
    expect(File.exist?(leaf)).to be(false)
    expect(result["ok"]).to be(true)
  end

  it "archives a leaf past archive_after into <root>/archive and removes the original" do
    store, leaf = build_store("{ archive_after: 30d }")
    result = sweep(store)
    expect(result["archived"]).to eq(["proposals.notes.old"])
    expect(result["expired"]).to eq([])
    expect(File.exist?(leaf)).to be(false)
    expect(File.exist?(File.join(root, "archive", "zones", "proposals", "notes", "old.md"))).to be(true)
  end
end
