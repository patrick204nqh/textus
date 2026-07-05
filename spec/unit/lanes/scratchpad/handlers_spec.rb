RSpec.describe Textus::Lanes::Scratchpad::Handlers do
  describe ".session_open" do
    it "creates session entry" do
      ctx = instance_double("Textus::Protocol::Handlers::CommandContext")
      manifest = double("Manifest")
      data = double("ManifestData")
      mentry = double("Mentry")
      allow(manifest).to receive(:data).and_return(data)
      allow(data).to receive(:entries).and_return([mentry])
      allow(mentry).to receive(:key).and_return("scratchpad.sessions")
      allow(ctx).to receive(:manifest).and_return(manifest)
      allow(ctx).to receive(:container).and_return(nil)
      allow(ctx).to receive(:put)
      allow(SecureRandom).to receive(:uuid).and_return("test-uuid-123")

      result = described_class.session_open(ctx:, call: nil)
      expect(result["session_id"]).to eq("test-uuid-123")
      expect(result["status"]).to eq("active")
    end
  end

  describe ".session_close" do
    it "seals an active session" do
      ctx = instance_double("Textus::Protocol::Handlers::CommandContext")
      manifest = double("Manifest")
      data = double("ManifestData")
      mentry = double("Mentry")
      allow(manifest).to receive(:data).and_return(data)
      allow(data).to receive(:entries).and_return([mentry])
      allow(mentry).to receive(:key).and_return("scratchpad.sessions")
      allow(ctx).to receive(:manifest).and_return(manifest)
      env = instance_double("Envelope", body: JSON.generate("session_id" => "abc", "status" => "active"))
      allow(ctx).to receive(:read).with(key: "scratchpad.sessions.abc.session").and_return(env)
      allow(ctx).to receive(:put)

      result = described_class.session_close(session_id: "abc", ctx:, call: nil)
      expect(result["status"]).to eq("sealed")
    end

    it "returns error for missing session" do
      ctx = instance_double("Textus::Protocol::Handlers::CommandContext")
      allow(ctx).to receive(:read).and_return(nil)

      expect { described_class.session_close(session_id: "missing", ctx:, call: nil) }
        .to raise_error(Textus::UsageError, /session not found/)
    end
  end
end
