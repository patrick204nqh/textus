RSpec.describe Textus::Lanes::Proposal::Handlers do
  describe ".propose" do
    it "writes to the proposal zone with prefixed key" do
      container = instance_double(Container)
      manifest = instance_double(Manifest, policy: instance_double("Policy"), resolver: instance_double("Resolver"))
      writer = instance_double("Writer")
      allow(container).to receive_messages(manifest:, writer:)
      ctx = Textus::Protocol::HandlerContext.new(container)
      allow(manifest.policy).to receive(:propose_lane_for).with("human").and_return("proposals")
      entry = double("entry", entry: instance_double(Mentry))
      allow(manifest.resolver).to receive(:resolve).with("proposals.decisions.feature-x").and_return(entry)
      env = instance_double(Envelope)
      allow(env).to receive(:to_h_for_wire).and_return({ "key" => "proposals.decisions.feature-x", "uid" => "abc" })
      allow(writer).to receive(:put).and_return(env)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.propose(
        key: "decisions.feature-x", meta: { "proposal" => { "target_key" => "knowledge.foo" } },
        body: "some body", content: nil, ctx:, call:
      )

      expect(writer).to have_received(:put).with(
        "proposals.decisions.feature-x",
        mentry: entry.entry,
        if_etag: nil,
        call:,
        payload: instance_of(Textus::Value::Payload),
      )
      expect(result).to eq({ "key" => "proposals.decisions.feature-x", "uid" => "abc" })
    end

    it "returns error when role has no propose lane" do
      container = instance_double(Container)
      manifest = instance_double(Manifest, policy: instance_double("Policy"))
      allow(container).to receive(:manifest).and_return(manifest)
      ctx = Textus::Protocol::HandlerContext.new(container)
      allow(manifest.policy).to receive(:propose_lane_for).with("viewer").and_return(nil)

      call = instance_double(Call, role: "viewer", correlation_id: "abc")

      result = described_class.propose(
        key: "test", ctx:, call:,
      )

      expect(result).to have_key(:error)
      expect(result[:error][:code]).to eq("propose_forbidden")
    end
  end

  describe ".accept" do
    it "reads proposal and writes to target, then deletes proposal" do
      container = instance_double(Container)
      reader = instance_double("Reader")
      writer = instance_double("Writer")
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      allow(container).to receive_messages(reader:, writer:, manifest:)
      ctx = Textus::Protocol::HandlerContext.new(container)

      pending_env = instance_double(Envelope,
                                    meta: { "proposal" => { "target_key" => "knowledge.foo", "action" => "put" } },
                                    body: "proposed content")
      allow(reader).to receive(:read).with("proposals.test").and_return(pending_env)

      entry = double("entry", entry: instance_double(Mentry))
      allow(manifest.resolver).to receive(:resolve).with("knowledge.foo").and_return(entry)
      allow(writer).to receive(:put)
      allow(writer).to receive(:delete)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.accept(pending_key: "proposals.test", dry_run: false, ctx:, call:)

      expect(writer).to have_received(:put).with("knowledge.foo", anything)
      expect(writer).to have_received(:delete).with("proposals.test", anything)
      expect(result["accepted"]).to eq("proposals.test")
    end

    it "returns dry_run diff without writing" do
      container = instance_double(Container)
      reader = instance_double("Reader")
      allow(container).to receive(:reader).and_return(reader)
      allow(container).to receive(:writer)
      ctx = Textus::Protocol::HandlerContext.new(container)

      pending_env = instance_double(Envelope,
                                    meta: { "proposal" => { "target_key" => "knowledge.foo", "action" => "put" } },
                                    body: "new content")
      allow(reader).to receive(:read).with("proposals.test").and_return(pending_env)
      allow(reader).to receive(:read).with("knowledge.foo").and_return(
        instance_double(Envelope, body: "old content", meta: { "_meta" => {} }),
      )
      allow(Textus::Protocol::Diff).to receive_messages(body: { "type" => "diff" }, meta: {}, summary: { "changes" => 1 })

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.accept(pending_key: "proposals.test", dry_run: true, ctx:, call:)

      expect(result["dry_run"]).to be true
      expect(result).to have_key("body")
    end

    it "returns error when proposal block missing" do
      container = instance_double(Container)
      reader = instance_double("Reader")
      allow(container).to receive(:reader).and_return(reader)
      ctx = Textus::Protocol::HandlerContext.new(container)
      env = instance_double(Envelope, meta: {})
      allow(reader).to receive(:read).and_return(env)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.accept(pending_key: "bad", ctx:, call:)
      expect(result[:error][:code]).to eq("proposal_error")
    end
  end

  describe ".reject" do
    it "deletes the proposal and returns result" do
      container = instance_double(Container)
      reader = instance_double("Reader")
      writer = instance_double("Writer")
      manifest = instance_double(Manifest, policy: instance_double("Policy"), resolver: instance_double("Resolver"))
      allow(container).to receive_messages(reader:, writer:, manifest:)
      ctx = Textus::Protocol::HandlerContext.new(container)

      mentry = instance_double(Mentry)
      allow(mentry).to receive(:in_proposal_lane?).and_return(true)
      entry = double("entry", entry: mentry)
      allow(manifest.resolver).to receive(:resolve).with("proposals.test").and_return(entry)

      env = instance_double(Envelope, meta: { "proposal" => { "target_key" => "knowledge.foo" } })
      allow(reader).to receive(:read).with("proposals.test").and_return(env)
      allow(writer).to receive(:delete)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.reject(pending_key: "proposals.test", reason: "not needed", ctx:, call:)

      expect(writer).to have_received(:delete).with("proposals.test", if_etag: nil, mentry:, call:)
      expect(result["rejected"]).to eq("proposals.test")
      expect(result["reason"]).to eq("not needed")
    end

    it "returns error when key is not in proposal zone" do
      container = instance_double(Container)
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"), policy: instance_double("Policy"))
      allow(container).to receive(:manifest).and_return(manifest)
      ctx = Textus::Protocol::HandlerContext.new(container)
      mentry = instance_double(Mentry)
      allow(mentry).to receive_messages(in_proposal_lane?: false, lane: "knowledge")
      entry = double("entry", entry: mentry)
      allow(manifest.resolver).to receive(:resolve).with("knowledge.foo").and_return(entry)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.reject(pending_key: "knowledge.foo", ctx:, call:)
      expect(result[:error][:code]).to eq("proposal_error")
    end
  end

  describe ".diff" do
    it "returns diff between proposal and target" do
      container = instance_double(Container)
      reader = instance_double("Reader")
      manifest = instance_double(Manifest)
      manifest_data = double("ManifestData")
      allow(manifest).to receive(:data).and_return(manifest_data)
      allow(container).to receive_messages(reader:, manifest:)
      ctx = Textus::Protocol::HandlerContext.new(container)

      env = instance_double(Envelope,
                            meta: { "proposal" => { "target_key" => "knowledge.foo" }, "_meta" => { "schema" => "v2" } },
                            body: "new body")
      allow(reader).to receive(:read).with("proposals.test").and_return(env)

      target_env = instance_double(Envelope, body: "old body", meta: { "_meta" => {} })
      allow(reader).to receive(:read).with("knowledge.foo").and_return(target_env)

      entry = double("entry", key: "knowledge.foo", schema_ref: "v1")
      allow(manifest_data).to receive(:entries).and_return([entry])

      allow(Textus::Protocol::Diff).to receive_messages(body: { "type" => "diff" }, meta: {},
                                                        schema: { "schema" => { "from" => "v1", "to" => "v2" } }, summary: { "changes" => 2 })

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.diff(pending_key: "proposals.test", ctx:, call:)

      expect(result["pending_key"]).to eq("proposals.test")
      expect(result["target_key"]).to eq("knowledge.foo")
      expect(result).to have_key("body")
      expect(result).to have_key("schema")
      expect(result).to have_key("summary")
    end

    it "returns error when proposal block missing" do
      container = instance_double(Container)
      reader = instance_double("Reader")
      allow(container).to receive(:reader).and_return(reader)
      ctx = Textus::Protocol::HandlerContext.new(container)
      env = instance_double(Envelope, meta: {})
      allow(reader).to receive(:read).and_return(env)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.diff(pending_key: "bad", ctx:, call:)
      expect(result[:error][:code]).to eq("proposal_error")
    end
  end
end
