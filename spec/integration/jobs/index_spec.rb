# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Store::Jobs::Index do
  include_context "textus_store_fixture"

  let(:files) { { "data/knowledge/a.md" => "---\ntitle: A\n---\nsearch body\n" } }

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML, files: files)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
    YAML
  end

  it "rebuilds the SQLite index" do
    result = described_class.new.call(container: store.container, call: test_ctx(role: "automation"))

    expect(result).to eq({ indexed: 1 })
    store_port = Textus::Port::Store.new(root: root).setup!
    keys = store_port.connection.execute("SELECT key FROM entries").map { |row| row["key"] }
    expect(keys).to eq(["knowledge.a"])
    store_port.close
  end
end
