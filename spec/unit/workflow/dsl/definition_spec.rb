RSpec.describe Textus::Workflow::DSL::Definition do
  subject(:defn) { described_class.new("test_workflow") }

  it "stores the name" do
    expect(defn.name).to eq("test_workflow")
  end

  it "records a step block" do
    defn.step(:fetch) { |data, _ctx| data }
    expect(defn.steps.length).to eq(1)
    expect(defn.steps.first.name).to eq(:fetch)
  end

  it "records a step callable class" do
    klass = Class.new { def self.call(data, _ctx) = data }
    defn.step(:fetch, klass)
    expect(defn.steps.first.callable).to eq(klass)
  end

  it "records step timeout" do
    defn.step(:fetch, timeout: 15) { |d, _c| d }
    expect(defn.steps.first.timeout).to eq(15)
  end

  it "raises when step has no block or callable" do
    expect { defn.step(:fetch) }.to raise_error(ArgumentError, /fetch/)
  end

  describe "#match?" do
    before { defn.match("artifacts.feeds.github.*") }

    it { expect(defn.match?("artifacts.feeds.github.repos")).to be true }
    it { expect(defn.match?("artifacts.feeds.other.x")).to be false }
  end
end
