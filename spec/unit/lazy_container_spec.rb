RSpec.describe Textus::LazyContainer do
  subject(:container) { described_class.new { double(foo: :bar) } }

  it "delegates method calls to the resolved object" do
    expect(container.foo).to eq(:bar)
  end

  it "calls the factory only once" do
    count = 0
    c = described_class.new { double(foo: count += 1) }
    expect(c.foo).to eq(1)
    expect(c.foo).to eq(1)
  end

  it "responds_to? delegates to the resolved object" do
    expect(container).to respond_to(:foo)
  end
end
