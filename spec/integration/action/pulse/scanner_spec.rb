RSpec.describe Textus::Action::Pulse::Scanner do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "returns an array of freshness rows" do
    rows = described_class.new.call(container: store.container, call: test_ctx)
    expect(rows).to be_an(Array)
    expect(rows.first).to include(:key, :lane, :status)
  end
end
