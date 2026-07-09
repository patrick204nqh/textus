RSpec.describe Textus::Protocol::Gate do
  let(:store_engine) { double("StoreEngine") }
  let(:manifest) { instance_double(Textus::Protocol::Manifest, policy: policy) }
  let(:policy) { instance_double(Textus::Protocol::Manifest::Policy) }
  let(:layout) { instance_double("Layout") }
  let(:store) { instance_double(Textus::Infra::Store, audit_log: audit_log) }
  let(:audit_log) { double("AuditLog", latest: { seq: 99 }) }
  let(:container) { double("Container", manifest:, store:, layout:) }
  let(:session_store) { instance_double(Textus::Protocol::SessionStore) }
  let(:gate) { described_class.new(store_engine:, container:, session_store:, default_role: "agent") }

  def build_spec(verb:, category: :read, lane: nil, system: false, args: [])
    double("VerbSpec",
      verb:, category:, lane:, system?: system,
      read?: category == :read, write?: category == :write,
      required_args: args, args:)
  end

  before do
    allow(Textus::Protocol::VerbRegistry).to receive(:for).and_return(nil)
  end

  describe "#dispatch" do
    before do
      allow(Textus::Value::Etag).to receive(:for_contract).and_return("sha256:stub")
    end

    it "raises on non-Request input" do
      expect { gate.dispatch("bad") }
        .to raise_error(Textus::UsageError, /Request expected/)
    end

    it "raises on unknown verb" do
      req = Textus::Adapters::Request.new(verb: :unknown)
      expect { gate.dispatch(req) }
        .to raise_error(Textus::UsageError, /unknown verb/)
    end

    it "dispatches to lane handler for lane verbs" do
      spec = build_spec(verb: :ingest, category: :write, lane: :ingest)
      allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:ingest).and_return(spec)
      allow(policy).to receive(:allowed!)
      allow(session_store).to receive(:create).and_return({ id: "s1", role: "agent", cursor_seq: 0 })
      allow(session_store).to receive(:save)

      handler = class_double("Handlers", ingest: { ok: true })
      allow(Textus::Protocol::Lane).to receive(:handler_for).with(:ingest).and_return(handler)

      req = Textus::Adapters::Request.new(verb: :ingest, params: { kind: "url", slug: "test" })
      result = gate.dispatch(req)
      expect(result).to eq({ ok: true })
    end

    context "with session_store" do
      let(:key_arg) { double("ArgSpec", name: :key, default: nil) }

      it "creates session when no session_id" do
        spec = build_spec(verb: :get, category: :read, args: [key_arg])
        allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:get).and_return(spec)
        allow(store_engine).to receive(:read).with(key: "test") { raise Textus::UnknownKey.new("test") }
        allow(session_store).to receive(:create).and_return({ id: "s1", role: "agent", cursor_seq: 0 })

        req = Textus::Adapters::Request.new(verb: :get, params: { key: "test" })
        expect { gate.dispatch(req) }.to raise_error(Textus::UnknownKey)
      end

      it "resumes existing session when session_id provided" do
        spec = build_spec(verb: :get, category: :read, args: [key_arg])
        allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:get).and_return(spec)
        allow(store_engine).to receive(:read).with(key: "test") { raise Textus::UnknownKey.new("test") }

        expect(session_store).to receive(:find).with("existing-id").and_return(
          { id: "existing-id", role: "agent", cursor_seq: 5 }
        )

        req = Textus::Adapters::Request.new(verb: :get, params: { key: "test" }, session_id: "existing-id")
        expect { gate.dispatch(req) }.to raise_error(Textus::UnknownKey)
      end
    end

    context "without session_store" do
      let(:session_store) { nil }

      it "dispatches without session persistence" do
        spec = build_spec(verb: :list, category: :read)
        allow(Textus::Protocol::VerbRegistry).to receive(:for).with(:list).and_return(spec)
        allow(store_engine).to receive(:list).and_return([])

        req = Textus::Adapters::Request.new(verb: :list)
        result = gate.dispatch(req)
        expect(result).to eq([])
      end
    end
  end
end
