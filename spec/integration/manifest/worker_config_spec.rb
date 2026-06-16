require "spec_helper"

RSpec.describe Textus::Manifest::Data do # worker config
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
    YAML
  end

  it "defaults pool/poll/lease_ttl/max_attempts when worker: is absent" do
    cfg = store.manifest.data.worker_config
    expect(cfg[:pool]).to eq(4)
    expect(cfg[:poll]).to eq(5)
    expect(cfg[:lease_ttl]).to eq(60)
    expect(cfg[:max_attempts]).to eq(3)
  end
end
