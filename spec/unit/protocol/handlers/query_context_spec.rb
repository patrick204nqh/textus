RSpec.describe Textus::Protocol::Handlers::QueryContext do
  subject(:ctx) { described_class.new(store_engine, container, call) }

  let(:store_engine) { instance_double("Textus::Protocol::StoreEngine") }
  let(:container) { instance_double("Textus::Protocol::Container") }
  let(:call) { instance_double("Textus::Value::Call") }
  let(:store) { instance_double("Textus::Infra::Store") }

  before do
    allow(container).to receive_messages(manifest: double, schemas: double, layout: double, store: store)
    allow(store).to receive_messages(link_store: double, entry_index: double, cursor_store: double)
  end

  it "exposes call" do
    expect(ctx.call).to eq(call)
  end

  it "delegates read to store_engine" do
    expect(store_engine).to receive(:read).with(key: "test.key")
    ctx.read(key: "test.key")
  end

  it "delegates resolve to store_engine" do
    expect(store_engine).to receive(:resolve).with(key: "test.key")
    ctx.resolve(key: "test.key")
  end

  it "delegates list to store_engine" do
    expect(store_engine).to receive(:list).with(prefix: "test")
    ctx.list(prefix: "test")
  end

  it "delegates exists? to store_engine" do
    expect(store_engine).to receive(:exists?).with(key: "test.key")
    ctx.exists?(key: "test.key")
  end

  it "delegates mentry_for to store_engine" do
    expect(store_engine).to receive(:mentry_for).with(key: "test.key")
    ctx.mentry_for(key: "test.key")
  end

  it "does not respond to put" do
    expect { ctx.put(key: "test", call: double) }.to raise_error(NoMethodError)
  end

  it "does not respond to delete" do
    expect { ctx.delete(key: "test", call: double) }.to raise_error(NoMethodError)
  end

  it "does not respond to move" do
    expect { ctx.move(from_key: "a", to_key: "b", call: double) }.to raise_error(NoMethodError)
  end

  it "exposes manifest via container" do
    expect(ctx.manifest).to eq(container.manifest)
  end

  it "exposes schemas via container" do
    expect(ctx.schemas).to eq(container.schemas)
  end
end
