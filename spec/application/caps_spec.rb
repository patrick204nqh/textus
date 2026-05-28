require "spec_helper"

RSpec.describe Textus::Application do
  describe Textus::Application::ReadCaps do
    it "exposes manifest, file_store, schemas, root, audit_log, events" do
      caps = described_class.new(manifest: :m, file_store: :fs, schemas: :s, root: "/tmp", audit_log: :al, events: :ev)
      expect(caps.manifest).to eq(:m)
      expect(caps.file_store).to eq(:fs)
      expect(caps.schemas).to eq(:s)
      expect(caps.root).to eq("/tmp")
      expect(caps.audit_log).to eq(:al)
      expect(caps.events).to eq(:ev)
    end
  end

  describe Textus::Application::WriteCaps do
    it "extends ReadCaps with audit_log, events, authorizer" do
      caps = described_class.new(
        manifest: :m, file_store: :fs, schemas: :s, root: "/tmp",
        audit_log: :al, events: :ev, authorizer: :az
      )
      expect(caps.read).to be_a(Textus::Application::ReadCaps)
      expect(caps.read.manifest).to eq(:m)
      expect(caps.read.audit_log).to eq(:al)
      expect(caps.read.events).to eq(:ev)
      expect(caps.audit_log).to eq(:al)
      expect(caps.events).to eq(:ev)
      expect(caps.authorizer).to eq(:az)
    end
  end

  describe Textus::Application::HookCaps do
    it "carries events, rpc, manifest, root" do
      caps = described_class.new(events: :ev, rpc: :rpc, manifest: :m, root: "/tmp")
      expect(caps.events).to eq(:ev)
      expect(caps.rpc).to eq(:rpc)
      expect(caps.manifest).to eq(:m)
      expect(caps.root).to eq("/tmp")
    end
  end
end
