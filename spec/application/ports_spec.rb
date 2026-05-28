# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Ports do
  include_context "textus_store_fixture"

  let(:store) do
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries: []
    YAML
    Textus::Store.new(root)
  end

  it "builds from a Store" do
    ports = described_class.from_store(store)
    expect(ports.manifest).to     be(store.manifest)
    expect(ports.file_store).to   be(store.file_store)
    expect(ports.event_bus).to    be(store.bus)
    expect(ports.rpc_registry).to be(store.bus)
    expect(ports.audit_log).to    be(store.audit_log)
    expect(ports.schemas).to      be(store.schemas)
    expect(ports.root).to         eq(store.root)
  end

  it "is immutable" do
    ports = described_class.from_store(store)
    expect { ports.manifest = nil }.to raise_error(NoMethodError)
  end
end
