require "spec_helper"

RSpec.describe Textus::Dispatch::HandlerResolver do
  before do
    stub_const("FakeContract", Data.define(:key))
  end

  let(:fake_manifest)  { instance_double(Textus::Manifest) }
  let(:fake_job_store) { instance_double(Textus::Port::Store) }

  let(:ctx) do
    Textus::Store::Infrastructure.new(
      manifest: fake_manifest, file_store: :fs, schemas: :sc,
      audit_log: :al, job_store: fake_job_store, layout: :ly,
      link_edge_store: :les, workflows: :wf, event_bus: :eb,
      freshness_evaluator: :fe, trace_buffer: :tb, pipeline: nil
    )
  end

  let(:fake_handler) do
    Module.new do
      const_set(:HANDLES, FakeContract)
      const_set(:NEEDS, %i[manifest job_store].freeze)

      def self.call(_command, _call, deps)
        Textus::Value::Result.success({ "deps_manifest" => deps.manifest })
      end
    end
  end

  describe ".build" do
    it "registers the handler for its contract and injects declared deps" do
      registry = described_class.build(ctx, handlers: [fake_handler])
      handler_fn = registry.for(FakeContract)
      expect(handler_fn).not_to be_nil

      result = handler_fn.call(
        command: FakeContract.new(key: "x"),
        call: Textus::Value::Call.build(role: "human"),
      )
      expect(result.value["deps_manifest"]).to eq(fake_manifest)
    end

    it "raises Boot::DepNotFound when a NEEDS field is missing from Ctx" do
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
