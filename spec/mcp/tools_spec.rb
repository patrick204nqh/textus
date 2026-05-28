require "spec_helper"
require "tmpdir"
require "fileutils"
require "digest"

RSpec.describe Textus::MCP::Tools do
  include_context "textus_store_fixture"

  let(:manifest_yaml) do
    <<~YAML
      version: textus/3
      zones:
        - { name: identity, write_policy: [human] }
        - { name: working,  write_policy: [human, agent] }
        - { name: review,   write_policy: [agent] }
      entries:
        - { key: identity.self, path: identity/self.md, zone: identity, schema: null, owner: human:self, kind: leaf }
        - { key: working.note,  path: working/note.md,  zone: working,  schema: null, owner: human:self, kind: leaf }
    YAML
  end
  let(:store) { Textus::Store.new(root) }
  let(:etag) { Digest::SHA256.hexdigest(File.read(File.join(root, "manifest.yaml"))) }
  let(:session) do
    Textus::MCP::Session.new(role: "agent", cursor: 0, propose_zone: "review", manifest_etag: etag)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/review"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), manifest_yaml)
    File.write(File.join(root, "audit.log"), "")
  end

  describe ".call('boot', ...)" do
    it "returns the Boot.run envelope" do
      result = described_class.call("boot", session: session, store: store, args: {})
      expect(result).to include("zones", "entries", "agent_quickstart")
      expect(result["protocol"]).to eq(Textus::PROTOCOL)
    end
  end

  describe ".call('find', ...)" do
    it "lists keys filtered by zone" do
      result = described_class.call("find", session: session, store: store, args: { "zone" => "working" })
      expect(result).to be_an(Array)
    end
  end

  describe ".call('read', ...)" do
    it "raises ToolError for an unknown key" do
      expect do
        described_class.call("read", session: session, store: store, args: { "key" => "no.such.key" })
      end.to raise_error(Textus::MCP::ToolError)
    end
  end

  describe ".call('nope', ...)" do
    it "raises ToolError for an unknown tool" do
      expect do
        described_class.call("nope", session: session, store: store, args: {})
      end.to raise_error(Textus::MCP::ToolError, /unknown tool/)
    end
  end
end
