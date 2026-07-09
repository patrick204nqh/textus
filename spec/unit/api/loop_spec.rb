RSpec.describe Textus::API::Loop do
  let(:store) { instance_double(Textus::Protocol::SessionStore) }
  let(:session) { instance_double(Textus::API::Session, id: "s-1", payload: {}, role: "agent") }
  subject(:loop) { described_class.new([:intent, :constraint, :evidence], store:, session:) }

  before do
    allow(store).to receive(:update_payload)
  end

  it "enters first node on first" do
    loop.first
    expect(loop.current.node).to eq(:intent)
  end

  it "enters a node path" do
    loop.enter([:intent, "topic-name"])
    expect(loop.current.topic).to eq("topic-name")
  end

  it "exits current node" do
    loop.first
    loop.exit
    expect(loop.current).to be_nil
  end

  it "rejects backward jump to non-reflection node" do
    loop.enter([:evidence])
    expect { loop.enter([:constraint]) }.to raise_error(Textus::UsageError)
  end

  it "persists to store on each navigation" do
    expect(store).to receive(:update_payload).with("s-1", hash_including(:stack))
    loop.first
  end

  it "returns status hash" do
    loop.first
    status = loop.status
    expect(status[:current_node]).to eq("intent")
    expect(status[:available_nodes]).to include("constraint")
  end

  it "restores stack from payload" do
    restored = described_class.new(
      [:intent, :constraint],
      store:, session: instance_double(Textus::API::Session, id: "s-1", payload: { "stack" => [["intent"]] }, role: "agent"),
    )
    expect(restored.current.node).to eq(:intent)
  end

  it "serializes to hash" do
    loop.first
    h = loop.to_h
    expect(h[:stack]).to eq([["intent"]])
  end

  it "does not require a gate" do
    l = described_class.new([:intent], store:, session:)
    expect { l.first }.not_to raise_error
  end
end
