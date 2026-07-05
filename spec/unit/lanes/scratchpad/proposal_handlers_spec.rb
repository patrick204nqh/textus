RSpec.describe Textus::Lanes::Scratchpad::Handlers do
  def mock_container(manifest:, store:)
    c = double("Container")
    schemas = instance_double(Textus::Protocol::Schema::Registry)
    allow(schemas).to receive(:fetch_or_nil).and_return(nil)
    allow(c).to receive_messages(manifest:, store:, layout: nil, workflow_registry: nil, schemas:)
    c
  end

  describe ".propose" do
    it "writes to scratchpad.proposals with prefixed key" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      call = instance_double(Call, role: "human", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::CommandContext.new(store_engine, container, call:)

      target_mentry = instance_double(Mentry, naming: nil, schema: nil, format: "markdown", lane: "knowledge")
      target_path = "/tmp/foo.md"
      target_resolution = instance_double(Textus::Protocol::Manifest::Resolver::Resolution, entry: target_mentry, path: target_path)
      allow(manifest.resolver).to receive(:resolve).with("knowledge.foo").and_return(target_resolution)

      proposals_mentry = instance_double(Mentry)
      proposals_entry = double("entry", entry: proposals_mentry)
      allow(manifest.resolver).to receive(:resolve).with("scratchpad.proposals.decisions.feature-x").and_return(proposals_entry)
      env = instance_double(Envelope)
      allow(env).to receive(:to_h_for_wire).and_return({ "key" => "scratchpad.proposals.decisions.feature-x", "uid" => "abc" })
      allow(store_engine).to receive(:put).and_return(env)

      result = described_class.propose(
        key: "decisions.feature-x", meta: { "proposal" => { "target_key" => "knowledge.foo" } },
        data: "some body", ctx:, call:
      )

      expect(store_engine).to have_received(:put).with(
        hash_including(key: "scratchpad.proposals.decisions.feature-x",
                       meta: { "proposal" => { "target_key" => "knowledge.foo" } },
                       body: "some body", call:),
      )
      expect(result).to eq({ "key" => "scratchpad.proposals.decisions.feature-x", "uid" => "abc" })
    end
  end

  describe ".accept" do
    it "reads proposal and writes to target, then deletes proposal" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      call = instance_double(Call, role: "human", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::CommandContext.new(store_engine, container, call:)

      pending_env = instance_double(Envelope,
                                    meta: { "proposal" => { "target_key" => "knowledge.foo", "action" => "put" },
                                            "name" => "test-entry" },
                                    body: "proposed content",
                                    content: nil)
      allow(store_engine).to receive(:read).with(key: "scratchpad.proposals.test").and_return(pending_env)

      target_mentry = instance_double(Mentry, naming: nil, schema: nil, format: "markdown", lane: "knowledge")
      target_resolution = instance_double(Textus::Protocol::Manifest::Resolver::Resolution, entry: target_mentry, path: "/tmp/foo.md")
      allow(manifest.resolver).to receive(:resolve).with("knowledge.foo").and_return(target_resolution)
      allow(store_engine).to receive(:put)
      allow(store_engine).to receive(:delete)

      result = described_class.accept(pending_key: "scratchpad.proposals.test", dry_run: false, ctx:, call:)

      expect(store_engine).to have_received(:put).with(
        hash_including(key: "knowledge.foo", meta: { "name" => "test-entry" }, content: nil),
      )
      expect(store_engine).to have_received(:delete).with(hash_including(key: "scratchpad.proposals.test"))
      expect(result["accepted"]).to eq("scratchpad.proposals.test")
    end

    it "preserves structured content from JSON proposals on accept" do
      manifest = instance_double(Manifest, resolver: instance_double("Resolver"))
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      call = instance_double(Call, role: "human", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::CommandContext.new(store_engine, container, call:)

      pending_env = instance_double(Envelope,
                                    meta: { "proposal" => { "target_key" => "knowledge.foo", "action" => "put" } },
                                    body: nil,
                                    content: { "data" => 1 })
      allow(store_engine).to receive(:read).with(key: "scratchpad.proposals.test").and_return(pending_env)

      target_mentry = instance_double(Mentry, naming: nil, schema: nil, format: "markdown", lane: "knowledge")
      target_resolution = instance_double(Textus::Protocol::Manifest::Resolver::Resolution, entry: target_mentry, path: "/tmp/foo.md")
      allow(manifest.resolver).to receive(:resolve).with("knowledge.foo").and_return(target_resolution)
      allow(store_engine).to receive(:put)
      allow(store_engine).to receive(:delete)

      described_class.accept(pending_key: "scratchpad.proposals.test", dry_run: false, ctx:, call:)

      expect(store_engine).to have_received(:put).with(
        hash_including(key: "knowledge.foo", content: { "data" => 1 }),
      )
    end

    it "returns dry_run diff without writing" do
      manifest = instance_double(Manifest)
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      call = instance_double(Call, role: "human", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::CommandContext.new(store_engine, container, call:)

      pending_env = instance_double(Envelope,
                                    meta: { "proposal" => { "target_key" => "knowledge.foo", "action" => "put" } },
                                    body: "new content")
      allow(store_engine).to receive(:read).with(key: "scratchpad.proposals.test").and_return(pending_env)
      allow(store_engine).to receive(:read).with(key: "knowledge.foo").and_return(
        instance_double(Envelope, body: "old content", meta: { "_meta" => {} }),
      )
      allow(Textus::Protocol::Diff).to receive_messages(body: { "type" => "diff" }, meta: {}, summary: { "changes" => 1 })

      result = described_class.accept(pending_key: "scratchpad.proposals.test", dry_run: true, ctx:, call:)

      expect(result["dry_run"]).to be true
      expect(result).to have_key("body")
    end

    it "returns error when proposal block missing" do
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      manifest = instance_double(Manifest)
      container = mock_container(manifest:, store:)
      call = instance_double(Call, role: "human", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::CommandContext.new(store_engine, container, call:)
      env = instance_double(Envelope, meta: {})
      allow(store_engine).to receive(:read).and_return(env)

      expect { described_class.accept(pending_key: "bad", ctx:, call:) }
        .to raise_error(Textus::ProposalError, /no proposal block/)
    end
  end

  describe ".reject" do
    it "deletes the proposal and returns result" do
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      manifest = instance_double(Manifest)
      container = mock_container(manifest:, store:)
      call = instance_double(Call, role: "human", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::CommandContext.new(store_engine, container, call:)

      env = instance_double(Envelope, meta: { "proposal" => { "target_key" => "knowledge.foo" } })
      allow(store_engine).to receive(:read).with(key: "scratchpad.proposals.test").and_return(env)
      allow(store_engine).to receive(:delete)

      result = described_class.reject(pending_key: "scratchpad.proposals.test", reason: "not needed", ctx:, call:)

      expect(store_engine).to have_received(:delete).with(hash_including(key: "scratchpad.proposals.test", call:))
      expect(result["rejected"]).to eq("scratchpad.proposals.test")
      expect(result["reason"]).to eq("not needed")
    end

    it "returns error when entry has no proposal block" do
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      manifest = instance_double(Manifest)
      container = mock_container(manifest:, store:)
      call = instance_double(Call, role: "human", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::CommandContext.new(store_engine, container, call:)
      env = instance_double(Envelope, meta: {})
      allow(store_engine).to receive(:read).and_return(env)

      expect { described_class.reject(pending_key: "scratchpad.proposals.test", ctx:, call:) }
        .to raise_error(Textus::ProposalError, /no proposal block/)
    end
  end

  describe ".diff" do
    it "returns diff between proposal and target" do
      manifest = instance_double(Manifest)
      manifest_data = double("ManifestData")
      allow(manifest).to receive(:data).and_return(manifest_data)
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      container = mock_container(manifest:, store:)
      call = instance_double(Call, role: "human", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::CommandContext.new(store_engine, container, call:)

      env = instance_double(Envelope,
                            meta: { "proposal" => { "target_key" => "knowledge.foo" }, "_meta" => { "schema" => "v2" } },
                            body: "new body")
      allow(store_engine).to receive(:read).with(key: "scratchpad.proposals.test").and_return(env)

      target_env = instance_double(Envelope, body: "old body", meta: { "_meta" => {} })
      allow(store_engine).to receive(:read).with(key: "knowledge.foo").and_return(target_env)

      entry = double("entry", key: "knowledge.foo", schema_ref: "v1")
      allow(manifest_data).to receive(:entries).and_return([entry])

      allow(Textus::Protocol::Diff).to receive_messages(body: { "type" => "diff" }, meta: {},
                                                        schema: { "schema" => { "from" => "v1", "to" => "v2" } }, summary: { "changes" => 2 })

      result = described_class.diff(pending_key: "scratchpad.proposals.test", ctx:, call:)

      expect(result["pending_key"]).to eq("scratchpad.proposals.test")
      expect(result["target_key"]).to eq("knowledge.foo")
      expect(result).to have_key("body")
      expect(result).to have_key("schema")
      expect(result).to have_key("summary")
    end

    it "returns error when proposal block missing" do
      store_engine = instance_double(Textus::Protocol::StoreEngine)
      store = instance_double(Textus::Infra::Store, file_system: nil)
      manifest = instance_double(Manifest)
      container = mock_container(manifest:, store:)
      call = instance_double(Call, role: "human", correlation_id: "abc")
      ctx = Textus::Protocol::Handlers::CommandContext.new(store_engine, container, call:)
      env = instance_double(Envelope, meta: {})
      allow(store_engine).to receive(:read).and_return(env)

      expect { described_class.diff(pending_key: "bad", ctx:, call:) }
        .to raise_error(Textus::ProposalError, /no proposal block/)
    end
  end
end
