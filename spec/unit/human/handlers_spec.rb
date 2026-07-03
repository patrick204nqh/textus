RSpec.describe Textus::Human::Handlers do
  describe ".accept" do
    it "reads proposal and writes to target, then deletes proposal" do
      container = instance_double("Container")
      reader = instance_double("Reader")
      writer = instance_double("Writer")
      manifest = instance_double("Manifest", resolver: instance_double("Resolver"))
      allow(container).to receive_messages(reader:, writer:, manifest:)

      pending_env = instance_double("Envelope",
        meta: { "proposal" => { "target_key" => "knowledge.foo", "action" => "put" } },
        body: "proposed content")
      allow(reader).to receive(:read).with("proposals.test").and_return(pending_env)

      entry = instance_double("Entry", entry: instance_double("Mentry"))
      allow(manifest.resolver).to receive(:resolve).with("knowledge.foo").and_return(entry)
      allow(writer).to receive(:put)
      allow(writer).to receive(:delete)

      call = instance_double("Call", role: "human", correlation_id: "abc")

      result = described_class.accept(pending_key: "proposals.test", dry_run: false, container:, call:)

      expect(writer).to have_received(:put).with("knowledge.foo", anything)
      expect(writer).to have_received(:delete).with("proposals.test", anything)
      expect(result["accepted"]).to eq("proposals.test")
    end

    it "returns dry_run diff without writing" do
      container = instance_double("Container")
      reader = instance_double("Reader")
      allow(container).to receive(:reader).and_return(reader)
      allow(container).to receive(:writer)

      pending_env = instance_double("Envelope",
        meta: { "proposal" => { "target_key" => "knowledge.foo", "action" => "put" } },
        body: "new content")
      allow(reader).to receive(:read).with("proposals.test").and_return(pending_env)
      allow(reader).to receive(:read).with("knowledge.foo").and_return(
        instance_double("Envelope", body: "old content", meta: { "_meta" => {} })
      )
      allow(Textus::Protocol::Diff).to receive(:body).and_return({ "type" => "diff" })
      allow(Textus::Protocol::Diff).to receive(:meta).and_return({})
      allow(Textus::Protocol::Diff).to receive(:summary).and_return({ "changes" => 1 })

      call = instance_double("Call", role: "human", correlation_id: "abc")

      result = described_class.accept(pending_key: "proposals.test", dry_run: true, container:, call:)

      expect(result["dry_run"]).to be true
      expect(result).to have_key("body")
    end

    it "returns error when proposal block missing" do
      container = instance_double("Container")
      reader = instance_double("Reader")
      allow(container).to receive(:reader).and_return(reader)
      env = instance_double("Envelope", meta: {})
      allow(reader).to receive(:read).and_return(env)

      call = instance_double("Call", role: "human", correlation_id: "abc")

      result = described_class.accept(pending_key: "bad", container:, call:)
      expect(result[:error][:code]).to eq("proposal_error")
    end
  end

  describe ".reject" do
    it "deletes the proposal and returns result" do
      container = instance_double("Container")
      reader = instance_double("Reader")
      writer = instance_double("Writer")
      manifest = instance_double("Manifest", policy: instance_double("Policy"), resolver: instance_double("Resolver"))
      allow(container).to receive_messages(reader:, writer:, manifest:)

      mentry = instance_double("Mentry")
      allow(mentry).to receive(:in_proposal_lane?).and_return(true)
      entry = instance_double("Entry", entry: mentry)
      allow(manifest.resolver).to receive(:resolve).with("proposals.test").and_return(entry)

      env = instance_double("Envelope", meta: { "proposal" => { "target_key" => "knowledge.foo" } })
      allow(reader).to receive(:read).with("proposals.test").and_return(env)
      allow(writer).to receive(:delete)

      call = instance_double("Call", role: "human", correlation_id: "abc")

      result = described_class.reject(pending_key: "proposals.test", reason: "not needed", container:, call:)

      expect(writer).to have_received(:delete).with("proposals.test", mentry:, call:)
      expect(result["rejected"]).to eq("proposals.test")
      expect(result["reason"]).to eq("not needed")
    end

    it "returns error when key is not in proposal zone" do
      container = instance_double("Container")
      manifest = instance_double("Manifest", resolver: instance_double("Resolver"), policy: instance_double("Policy"))
      allow(container).to receive(:manifest).and_return(manifest)
      mentry = instance_double("Mentry")
      allow(mentry).to receive(:in_proposal_lane?).and_return(false)
      allow(mentry).to receive(:lane).and_return("knowledge")
      entry = instance_double("Entry", entry: mentry)
      allow(manifest.resolver).to receive(:resolve).with("knowledge.foo").and_return(entry)

      call = instance_double("Call", role: "human", correlation_id: "abc")

      result = described_class.reject(pending_key: "knowledge.foo", container:, call:)
      expect(result[:error][:code]).to eq("proposal_error")
    end
  end

  describe ".diff" do
    it "returns diff between proposal and target" do
      container = instance_double("Container")
      reader = instance_double("Reader")
      manifest = instance_double("Manifest")
      manifest_data = double("ManifestData")
      allow(manifest).to receive(:data).and_return(manifest_data)
      allow(container).to receive_messages(reader:, manifest:)

      env = instance_double("Envelope",
        meta: { "proposal" => { "target_key" => "knowledge.foo" }, "_meta" => { "schema" => "v2" } },
        body: "new body")
      allow(reader).to receive(:read).with("proposals.test").and_return(env)

      target_env = instance_double("Envelope", body: "old body", meta: { "_meta" => {} })
      allow(reader).to receive(:read).with("knowledge.foo").and_return(target_env)

      entry = instance_double("Entry", key: "knowledge.foo", schema_ref: "v1")
      allow(manifest_data).to receive(:entries).and_return([entry])

      allow(Textus::Protocol::Diff).to receive(:body).and_return({ "type" => "diff" })
      allow(Textus::Protocol::Diff).to receive(:meta).and_return({})
      allow(Textus::Protocol::Diff).to receive(:schema).and_return({ "schema" => { "from" => "v1", "to" => "v2" } })
      allow(Textus::Protocol::Diff).to receive(:summary).and_return({ "changes" => 2 })

      call = instance_double("Call", role: "human", correlation_id: "abc")

      result = described_class.diff(pending_key: "proposals.test", container:, call:)

      expect(result["pending_key"]).to eq("proposals.test")
      expect(result["target_key"]).to eq("knowledge.foo")
      expect(result).to have_key("body")
      expect(result).to have_key("schema")
      expect(result).to have_key("summary")
    end

    it "returns error when proposal block missing" do
      container = instance_double("Container")
      reader = instance_double("Reader")
      allow(container).to receive(:reader).and_return(reader)
      env = instance_double("Envelope", meta: {})
      allow(reader).to receive(:read).and_return(env)

      call = instance_double("Call", role: "human", correlation_id: "abc")

      result = described_class.diff(pending_key: "bad", container:, call:)
      expect(result[:error][:code]).to eq("proposal_error")
    end
  end

  describe ".propose" do
    it "writes to the proposal zone with prefixed key" do
      container = instance_double("Container")
      manifest = instance_double("Manifest", policy: instance_double("Policy"), resolver: instance_double("Resolver"))
      writer = instance_double("Writer")
      allow(container).to receive_messages(manifest:, writer:)
      allow(manifest.policy).to receive(:propose_lane_for).with("human").and_return("proposals")
      entry = instance_double("Entry", entry: instance_double("Mentry"))
      allow(manifest.resolver).to receive(:resolve).with("proposals.decisions.feature-x").and_return(entry)
      env = instance_double("Envelope")
      allow(env).to receive(:to_h_for_wire).and_return({ "key" => "proposals.decisions.feature-x", "uid" => "abc" })
      allow(writer).to receive(:put).and_return(env)

      call = instance_double("Call", role: "human", correlation_id: "abc")

      result = described_class.propose(
        key: "decisions.feature-x", meta: { "proposal" => { "target_key" => "knowledge.foo" } },
        body: "some body", content: nil, container:, call:
      )

      expect(writer).to have_received(:put).with(
        "proposals.decisions.feature-x",
        mentry: entry.entry,
        call:,
        payload: instance_of(Textus::Value::Payload)
      )
      expect(result).to eq({ "key" => "proposals.decisions.feature-x", "uid" => "abc" })
    end

    it "returns error when role has no propose lane" do
      container = instance_double("Container")
      manifest = instance_double("Manifest", policy: instance_double("Policy"))
      allow(container).to receive(:manifest).and_return(manifest)
      allow(manifest.policy).to receive(:propose_lane_for).with("viewer").and_return(nil)

      call = instance_double("Call", role: "viewer", correlation_id: "abc")

      result = described_class.propose(
        key: "test", container:, call:
      )

      expect(result).to have_key(:error)
      expect(result[:error][:code]).to eq("propose_forbidden")
    end
  end
end
