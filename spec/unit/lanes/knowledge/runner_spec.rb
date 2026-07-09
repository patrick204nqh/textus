RSpec.describe Textus::Lanes::Knowledge::Runner do
  subject(:runner) { described_class.new(manifest) }

  let(:manifest) { instance_double(Textus::Protocol::Manifest, data: manifest_data) }
  let(:manifest_data) { instance_double(Textus::Protocol::Manifest::Data, entries: entries) }
  let(:entries) do
    [
      entry("knowledge.loop.intent"),
      entry("knowledge.loop.evidence"),
      entry("knowledge.loop.execution"),
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
end
