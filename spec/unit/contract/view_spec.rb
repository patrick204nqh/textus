require "spec_helper"

RSpec.describe Textus::Contract::View do
  let(:spec) do
    Class.new do
      extend Textus::Contract::DSL

      verb :demo
      view       { |r, _i| { "n" => r } }
      view(:cli) { |r, i| { "n" => r, "key" => i[:key] } }
      arg :key, String, positional: true
    end.contract
  end

  it "renders the default surface" do
    expect(described_class.render(spec, :default, 5, { key: "k" })).to eq("n" => 5)
  end

  it "renders the cli surface with inputs" do
    expect(described_class.render(spec, :cli, 5, { key: "k" })).to eq("n" => 5, "key" => "k")
  end
end
