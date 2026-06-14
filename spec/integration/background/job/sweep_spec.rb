RSpec.describe Textus::Background::Job::Sweep do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "calls Runtime::Retention::Apply with the scope" do
    scope = { "prefix" => nil, "lane" => nil }
    instance = instance_double(Textus::Background::Retention::Apply, call: nil)
    allow(Textus::Background::Retention::Apply).to receive(:new).and_return(instance)

    action = described_class.new(scope: scope)
    action.call(container: store.container, call: test_ctx)

    expect(instance).to have_received(:call)
  end
end
