require "spec_helper"

RSpec.describe Textus::Dispatch::HandlerResolver do
  before do
    stub_const("FakeContract", Data.define(:key))
  end

  let(:fake_manifest) { instance_double(Textus::Manifest) }
  let(:fake_event_store) { instance_double(Textus::Port::EventStore) }

  let(:storage)    { Textus::Store::Container::Storage.new(file_system: :fs, entry_store: nil, layout: :ly) }
  let(:events)     { Textus::Store::Container::Events.new(event_store: fake_event_store, workflows: :wf) }
  let(:governance) { Textus::Store::Container::Governance.new(manifest: fake_manifest, schemas: :sc) }
  let(:logging)    { Textus::Store::Container::Logging.new(audit_log: :al) }
  let(:links)      { Textus::Store::Container::Links.new(link_graph: :lg) }

  let(:ctx) do
    Textus::Store::Container.new(
      storage:, events:, governance:, logging:, links:,
      root: "/tmp", trace_buffer: :tb, ttl_evaluator: :fe, pipeline: nil
    )
  end

  let(:fake_handler) do
    Module.new do
      const_set(:HANDLES, FakeContract)
      const_set(:NEEDS, %i[manifest event_store].freeze)

      def self.call(_command, _call, deps)
        Textus::Value::Result.success({ "deps_manifest" => deps.manifest })
      end
    end
  end

  describe ".build" do
    it "registers the handler for its contract and injects declared deps" do
      registry = described_class.build(ctx, handlers: [fake_handler])
      handler_fn = registry[FakeContract]
      expect(handler_fn).not_to be_nil

      result = handler_fn.call(
        command: FakeContract.new(key: "x"),
        call: Textus::Value::Call.build(role: "human"),
      )
      expect(result.value["deps_manifest"]).to eq(fake_manifest)
    end

    it "raises Boot::DepNotFound when a NEEDS field is missing from the container" do
      bad_handler = Module.new do
        const_set(:HANDLES, FakeContract)
        const_set(:NEEDS, %i[nonexistent_field].freeze)
        def self.call(_command, _call, _deps); end
      end

      expect { described_class.build(ctx, handlers: [bad_handler]) }
        .to raise_error(Textus::Boot::DepNotFound, /nonexistent_field/)
    end
  end
end
