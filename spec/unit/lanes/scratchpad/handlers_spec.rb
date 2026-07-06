RSpec.describe Textus::Lanes::Scratchpad::Handlers do
  describe ".session_open" do
    it "creates session entry with dated key" do
      ctx = instance_double("Textus::Protocol::Handlers::CommandContext")
      manifest = double("Manifest")
      data = double("ManifestData")
      mentry = double("Mentry")
      allow(manifest).to receive(:data).and_return(data)
      allow(data).to receive(:entries).and_return([mentry])
      allow(mentry).to receive(:key).and_return("scratchpad.sessions")
      allow(ctx).to receive_messages(manifest: manifest, container: nil)
      allow(ctx).to receive(:put)
      allow(SecureRandom).to receive(:uuid).and_return("test-uuid-1234")
      allow(Time).to receive(:now).and_return(Time.new(2026, 7, 6, 12, 0, 0, "UTC"))

      result = described_class.session_open(ctx:, call: nil)
      expect(result["session_id"]).to eq("2026-07-06-test-uui")
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
