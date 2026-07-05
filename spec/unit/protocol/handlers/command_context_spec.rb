RSpec.describe Textus::Protocol::Handlers::CommandContext do
  subject(:ctx) { described_class.new(store_engine, container, call) }

  let(:store_engine) { instance_double("Textus::Protocol::StoreEngine") }
  let(:container) { instance_double("Textus::Protocol::Container") }
  let(:call) { instance_double("Textus::Value::Call") }
  let(:store) { instance_double("Textus::Infra::Store") }

  before do
    allow(container).to receive_messages(manifest: double, schemas: double, layout: double, store: store, workflows: double,
                                         workflow_registry: double)
    allow(store).to receive_messages(link_store: double, entry_index: double, cursor_store: double, audit_log: double,
                                     workflow_queue: double, file_system: double)
  end

  it "inherits from QueryContext" do
    expect(described_class.superclass).to eq(Textus::Protocol::Handlers::QueryContext)
  end

  it "has read methods (inherited)" do
    expect(store_engine).to receive(:read).with(key: "test.key")
    ctx.read(key: "test.key")
  end

  it "delegates put to store_engine" do
    expect(store_engine).to receive(:put).with(key: "test", meta: {}, body: nil, content: nil, call:)
    ctx.put(key: "test", meta: {}, body: nil, content: nil, call:)
  end

  it "delegates delete to store_engine" do
    expect(store_engine).to receive(:delete).with(key: "test", call:)
    ctx.delete(key: "test", call:)
  end

  it "delegates move to store_engine" do
    expect(store_engine).to receive(:move).with(from_key: "a", to_key: "b", call:)
    ctx.move(from_key: "a", to_key: "b", call:)
  end

  it "exposes audit_log" do
    expect(ctx.audit_log).to eq(store.audit_log)
  end

  it "exposes workflow_queue" do
    expect(ctx.workflow_queue).to eq(store.workflow_queue)
  end

  it "exposes file_system" do
    expect(ctx.file_system).to eq(store.file_system)
  end
end
