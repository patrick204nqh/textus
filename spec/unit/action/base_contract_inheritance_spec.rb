RSpec.describe Textus::Action::Base do
  it "extends Contract::DSL so all subclasses inherit it" do
    expect(described_class.singleton_class.ancestors).to include(Textus::Contract::DSL)
  end

  it "responds to Contract::DSL macros" do
    expect(described_class).to respond_to(:verb)
    expect(described_class).to respond_to(:arg)
    expect(described_class).to respond_to(:view)
    expect(described_class).to respond_to(:summary)
    expect(described_class).to respond_to(:surfaces)
  end
end
