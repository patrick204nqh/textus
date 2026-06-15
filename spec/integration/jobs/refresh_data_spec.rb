RSpec.describe Textus::Jobs::Refresh do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "converges the intake key via Pipeline::Engine" do
    key = "artifacts.intake.test"
    call = test_ctx
    spy = class_spy(Textus::Pipeline::Engine)
    stub_const("Textus::Pipeline::Engine", spy)

    action = described_class.new(key: key)
    action.call(container: store.container, call: call)

    expect(spy).to have_received(:converge)
      .with(container: store.container, call: call, keys: [key])
  end
end
