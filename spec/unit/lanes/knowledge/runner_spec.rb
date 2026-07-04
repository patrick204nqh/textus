RSpec.describe Textus::Lanes::Knowledge::Runner do
  subject(:runner) { described_class.new(manifest, cursor_store:) }

  let(:manifest) { instance_double(Textus::Protocol::Manifest, data: manifest_data) }
  let(:manifest_data) { instance_double(Textus::Protocol::Manifest::Data, entries: entries) }
  let(:cursor_store) { instance_double(Textus::Infra::Store::CursorStore) }
  let(:entries) do
    [
      entry("knowledge.loop.intent"),
      entry("knowledge.loop.evidence"),
      entry("knowledge.loop.execution"),
      entry("knowledge.loop.feedback.0001"), # child, not a node
      entry("knowledge.boot"),
    ]
  end

  def entry(key)
    instance_double(Textus::Protocol::Manifest::Entry::Base, key:)
  end

  describe "#loop_nodes" do
    it "returns entries matching knowledge.loop.<node> pattern" do
      expect(runner.loop_nodes.map(&:key)).to eq(%w[knowledge.loop.intent knowledge.loop.evidence knowledge.loop.execution])
    end
  end

  describe "#flow" do
    it "returns node names in order" do
      expect(runner.flow).to eq(%w[intent evidence execution])
    end
  end

  describe "#current_node" do
    it "returns the node at the given index" do
      node = runner.current_node(active_index: 1)
      expect(node[:name]).to eq("evidence")
      expect(node[:index]).to eq(1)
      expect(node[:total]).to eq(3)
    end

    it "wraps around via modulo" do
      node = runner.current_node(active_index: 3)
      expect(node[:name]).to eq("intent")
    end

    it "returns nil when no loop nodes" do
      empty_runner = described_class.new(manifest)
      allow(manifest_data).to receive(:entries).and_return([])
      expect(empty_runner.current_node).to be_nil
    end
  end

  describe "#advance" do
    it "returns the next node" do
      node = runner.advance(active_index: 0)
      expect(node[:name]).to eq("evidence")
      expect(node[:advanced]).to be(true)
    end
  end

  describe "#current_position" do
    it "reads from cursor_store and returns the node" do
      expect(cursor_store).to receive(:read_loop_position).with("agent").and_return(1)
      pos = runner.current_position("agent")
      expect(pos[:name]).to eq("evidence")
    end

    it "defaults to index 0 when cursor_store is nil" do
      r = described_class.new(manifest)
      pos = r.current_position("agent")
      expect(pos[:name]).to eq("intent")
    end
  end

  describe "#advance_role" do
    it "advances the cursor_store and returns next node" do
      expect(cursor_store).to receive(:read_loop_position).with("agent").and_return(0)
      expect(cursor_store).to receive(:write_loop_position).with("agent", 1)
      pos = runner.advance_role("agent")
      expect(pos[:name]).to eq("evidence")
    end
  end
end
