RSpec.describe Textus::Lanes::Scratchpad::Handlers do
  def mock_container(manifest:, store:)
    c = double("Container")
    allow(c).to receive_messages(manifest:, store:, layout: nil, workflow_registry: nil)
    c
  end

  def with_entry_store(store, entry_store)
    allow(Textus::Protocol::EntryStore).to receive(:new)
      .with(file_system: store.file_system, manifest: anything, layout: anything, store: store, workflow_registry: nil)
      .and_return(entry_store)
  end

  describe ".propose" do
    it "writes to scratchpad.proposals with prefixed key" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      with_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)
      entry = double("entry", entry: instance_double(Mentry))
      allow(manifest.resolver).to receive(:resolve).with("scratchpad.proposals.decisions.feature-x").and_return(entry)
      env = instance_double(Envelope)
      allow(env).to receive(:to_h_for_wire).and_return({ "key" => "scratchpad.proposals.decisions.feature-x", "uid" => "abc" })
      allow(entry_store).to receive(:put).and_return(env)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.propose(
        key: "decisions.feature-x", meta: { "proposal" => { "target_key" => "knowledge.foo" } },
        body: "some body", content: nil, ctx:, call:
      )

      expect(entry_store).to have_received(:put).with(
        "scratchpad.proposals.decisions.feature-x",
        mentry: entry.entry,
        if_etag: nil,
        call:,
        payload: instance_of(Textus::Value::Payload),
      )
      expect(result).to eq({ "key" => "scratchpad.proposals.decisions.feature-x", "uid" => "abc" })
    end
  end

  describe ".accept" do
    it "reads proposal and writes to target, then deletes proposal" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      with_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)

      pending_env = instance_double(Envelope,
                                    meta: { "proposal" => { "target_key" => "knowledge.foo", "action" => "put" } },
                                    body: "proposed content")
      allow(entry_store).to receive(:read).with("scratchpad.proposals.test").and_return(pending_env)

      entry = double("entry", entry: instance_double(Mentry))
      allow(manifest.resolver).to receive(:resolve).with("knowledge.foo").and_return(entry)
      allow(entry_store).to receive(:put)
      allow(entry_store).to receive(:delete)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.accept(pending_key: "scratchpad.proposals.test", dry_run: false, ctx:, call:)

      expect(entry_store).to have_received(:put).with("knowledge.foo", anything)
      expect(entry_store).to have_received(:delete).with("scratchpad.proposals.test", anything)
      expect(result["accepted"]).to eq("scratchpad.proposals.test")
    end

    it "returns dry_run diff without writing" do
      manifest = instance_double(Manifest)
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      with_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)

      pending_env = instance_double(Envelope,
                                    meta: { "proposal" => { "target_key" => "knowledge.foo", "action" => "put" } },
                                    body: "new content")
      allow(entry_store).to receive(:read).with("scratchpad.proposals.test").and_return(pending_env)
      allow(entry_store).to receive(:read).with("knowledge.foo").and_return(
        instance_double(Envelope, body: "old content", meta: { "_meta" => {} }),
      )
      allow(Textus::Protocol::Diff).to receive_messages(body: { "type" => "diff" }, meta: {}, summary: { "changes" => 1 })

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.accept(pending_key: "scratchpad.proposals.test", dry_run: true, ctx:, call:)

      expect(result["dry_run"]).to be true
      expect(result).to have_key("body")
    end

    it "returns error when proposal block missing" do
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      manifest = instance_double(Manifest)
      container = mock_container(manifest:, store:)
      with_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)
      env = instance_double(Envelope, meta: {})
      allow(entry_store).to receive(:read).and_return(env)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      expect { described_class.accept(pending_key: "bad", ctx:, call:) }
        .to raise_error(Textus::ProposalError, /no proposal block/)
    end
  end

  describe ".reject" do
    it "deletes the proposal and returns result" do
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      manifest = instance_double(Manifest)
      container = mock_container(manifest:, store:)
      with_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)

      env = instance_double(Envelope, meta: { "proposal" => { "target_key" => "knowledge.foo" } })
      allow(entry_store).to receive(:read).with("scratchpad.proposals.test").and_return(env)
      allow(entry_store).to receive(:delete)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.reject(pending_key: "scratchpad.proposals.test", reason: "not needed", ctx:, call:)

      expect(entry_store).to have_received(:delete).with("scratchpad.proposals.test", if_etag: nil, call:)
      expect(result["rejected"]).to eq("scratchpad.proposals.test")
      expect(result["reason"]).to eq("not needed")
    end

    it "returns error when entry has no proposal block" do
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      manifest = instance_double(Manifest)
      container = mock_container(manifest:, store:)
      with_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)
      env = instance_double(Envelope, meta: {})
      allow(entry_store).to receive(:read).and_return(env)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      expect { described_class.reject(pending_key: "scratchpad.proposals.test", ctx:, call:) }
        .to raise_error(Textus::ProposalError, /no proposal block/)
    end
  end

  describe ".diff" do
    it "returns diff between proposal and target" do
      manifest = instance_double(Manifest)
      manifest_data = double("ManifestData")
      allow(manifest).to receive(:data).and_return(manifest_data)
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      with_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)

      env = instance_double(Envelope,
                            meta: { "proposal" => { "target_key" => "knowledge.foo" }, "_meta" => { "schema" => "v2" } },
                            body: "new body")
      allow(entry_store).to receive(:read).with("scratchpad.proposals.test").and_return(env)

      target_env = instance_double(Envelope, body: "old body", meta: { "_meta" => {} })
      allow(entry_store).to receive(:read).with("knowledge.foo").and_return(target_env)

      entry = double("entry", key: "knowledge.foo", schema_ref: "v1")
      allow(manifest_data).to receive(:entries).and_return([entry])

      allow(Textus::Protocol::Diff).to receive_messages(body: { "type" => "diff" }, meta: {},
                                                        schema: { "schema" => { "from" => "v1", "to" => "v2" } }, summary: { "changes" => 2 })

      call = instance_double(Call, role: "human", correlation_id: "abc")

      result = described_class.diff(pending_key: "scratchpad.proposals.test", ctx:, call:)

      expect(result["pending_key"]).to eq("scratchpad.proposals.test")
      expect(result["target_key"]).to eq("knowledge.foo")
      expect(result).to have_key("body")
      expect(result).to have_key("schema")
      expect(result).to have_key("summary")
    end

    it "returns error when proposal block missing" do
      entry_store = instance_double(Textus::Protocol::EntryStore)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      manifest = instance_double(Manifest)
      container = mock_container(manifest:, store:)
      with_entry_store(store, entry_store)
      ctx = Textus::Protocol::HandlerContext.new(container)
      env = instance_double(Envelope, meta: {})
      allow(entry_store).to receive(:read).and_return(env)

      call = instance_double(Call, role: "human", correlation_id: "abc")

      expect { described_class.diff(pending_key: "bad", ctx:, call:) }
        .to raise_error(Textus::ProposalError, /no proposal block/)
    end
  end
end
