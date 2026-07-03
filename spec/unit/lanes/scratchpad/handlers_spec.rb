RSpec.describe Textus::Lanes::Scratchpad::Handlers do
  describe ".session_open" do
    it "creates session entry and workspace directories" do
      ctx = instance_double("HandlerContext")
      layout = instance_double("Layout")
      allow(ctx).to receive(:layout).and_return(layout)
      allow(layout).to receive(:lane_path).with("scratchpad").and_return("/tmp/textus/data/scratchpad")

      expect(FileUtils).to receive(:mkdir_p).with("/tmp/textus/data/scratchpad/sessions/test-uuid-123/scripts")
      expect(FileUtils).to receive(:mkdir_p).with("/tmp/textus/data/scratchpad/sessions/test-uuid-123/notes")
      expect(FileUtils).to receive(:mkdir_p).with("/tmp/textus/data/scratchpad/sessions/test-uuid-123/output")

      manifest = double("Manifest")
      data = double("ManifestData")
      mentry = double("Mentry")
      allow(manifest).to receive(:data).and_return(data)
      allow(data).to receive(:entries).and_return([mentry])
      allow(mentry).to receive(:key).and_return("scratchpad.sessions")
      allow(ctx).to receive(:manifest).and_return(manifest)
      allow(ctx).to receive(:write)
      allow(ctx).to receive(:payload).with(body: /"status":"active"/)
        .and_return(double("Payload"))
      allow(SecureRandom).to receive(:uuid).and_return("test-uuid-123")

      result = described_class.session_open(ctx:, call: nil)
      expect(result["session_id"]).to eq("test-uuid-123")
      expect(result["status"]).to eq("active")
    end
  end

  describe ".session_close" do
    it "seals an active session" do
      ctx = instance_double("HandlerContext")
      manifest = double("Manifest")
      data = double("ManifestData")
      mentry = double("Mentry")
      allow(manifest).to receive(:data).and_return(data)
      allow(data).to receive(:entries).and_return([mentry])
      allow(mentry).to receive(:key).and_return("scratchpad.sessions")
      allow(ctx).to receive(:manifest).and_return(manifest)
      env = instance_double("Envelope", body: JSON.generate("session_id" => "abc", "status" => "active"))
      allow(ctx).to receive(:read).with("scratchpad.sessions.abc.session").and_return(env)
      allow(ctx).to receive(:write)
      allow(ctx).to receive(:payload)

      result = described_class.session_close(session_id: "abc", ctx:, call: nil)
      expect(result["status"]).to eq("sealed")
    end

    it "returns error for missing session" do
      ctx = instance_double("HandlerContext")
      allow(ctx).to receive(:read).and_return(nil)

      result = described_class.session_close(session_id: "missing", ctx:, call: nil)
      expect(result[:error][:code]).to eq("not_found")
    end
  end
end