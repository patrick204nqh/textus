# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Gate::Auth do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge proposals feeds], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
        - { name: proposals, kind: queue }
        - { name: feeds,     kind: machine }
      entries:
        - { key: knowledge.doc,   path: data/knowledge/doc.md,   lane: knowledge, kind: leaf }
        - { key: proposals,       path: proposals,                lane: proposals, owner: human:self, kind: nested }
        - { key: feeds.data,      path: data/feeds/data.md,      lane: feeds,     kind: leaf }
    YAML
  end

  it "raises UsageError for an unmapped command class" do
    unknown = Class.new(Struct.new(:role, :key)) { def self.name = "Textus::Command::Ghost" }
    cmd = unknown.new("human", "knowledge.doc")
    auth = Textus::Gate::Auth.new(store.container)
    expect { auth.check!(cmd) }.to raise_error(Textus::UsageError, /unmapped command/)
  end
end
