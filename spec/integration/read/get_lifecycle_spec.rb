require "spec_helper"

RSpec.describe Textus::Read::Get do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[review], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: review, kind: canon }
      entries:
        - { key: review.oncall, path: review/oncall.md, zone: review, kind: leaf }
      rules:
        - match: "review.*"
          lifecycle: { ttl: 30d, on_expire: warn }
    YAML
  end

  let(:leaf) { File.join(root, "zones/review/oncall.md") }

  before do
    store
    File.write(leaf, "---\n_meta: {name: oncall, uid: aaaaaaaaaaaaaaaa}\n---\nbody\n")
    aged = Time.now - (40 * 86_400)
    File.utime(aged, aged, leaf)
  end

  def get = described_class.new(container: store.container, call: test_ctx(role: "human"))

  it "annotates an aged warn entry as stale on read, but never deletes it" do
    env = get.call("review.oncall")
    expect(env.freshness.stale).to be(true)
    expect(File.exist?(leaf)).to be(true)
  end

  it "does not act destructively on read even when on_expire is drop" do
    File.write(File.join(root, "manifest.yaml"),
               File.read(File.join(root, "manifest.yaml")).sub("on_expire: warn", "on_expire: drop"))
    g = described_class.new(container: Textus::Store.new(root).container, call: test_ctx(role: "human"))
    result = g.call("review.oncall")
    expect(result.freshness.stale).to be(true)
    expect(File.exist?(leaf)).to be(true)
  end
end
