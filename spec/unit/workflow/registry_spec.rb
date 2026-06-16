RSpec.describe Textus::Workflow::Registry do
  subject(:registry) { described_class.new }

  def make_definition(pattern)
    Textus::Workflow::DSL::Definition.new("test").tap { |d| d.match(pattern) }
  end

  describe "#for" do
    it "returns the first matching definition" do
      defn = make_definition("artifacts.feeds.github.*")
      registry.register(defn)
      expect(registry.for("artifacts.feeds.github.repos")).to eq(defn)
    end

    it "returns nil when nothing matches" do
      expect(registry.for("artifacts.feeds.github.repos")).to be_nil
    end

    it "first-registered wins on overlap" do
      first  = make_definition("artifacts.**")
      second = make_definition("artifacts.feeds.*")
      registry.register(first)
      registry.register(second)
      expect(registry.for("artifacts.feeds.github")).to eq(first)
    end
  end

  describe "#all" do
    it "returns a copy of registered definitions" do
      defn = make_definition("x.*")
      registry.register(defn)
      expect(registry.all).to eq([defn])
      expect(registry.all).not_to be(registry.all)
    end
  end
end
