RSpec.describe Textus::Workflow::Context do
  let(:entry) { instance_double(Textus::Manifest::Entry::Base, lane: :artifacts) }

  subject(:ctx) do
    described_class.new(key: "artifacts.feeds.x", entry: entry, config: { "token" => "abc" }, lane: "artifacts")
  end

  it { expect(ctx.key).to eq("artifacts.feeds.x") }
  it { expect(ctx.lane).to eq("artifacts") }
  it { expect(ctx.config).to eq({ "token" => "abc" }) }
  it "is frozen" do
    expect { ctx.instance_variable_set(:@key, "other") }.to raise_error(FrozenError)
  end
end
