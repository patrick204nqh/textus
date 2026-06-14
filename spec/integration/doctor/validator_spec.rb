RSpec.describe Textus::Doctor::Validator do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "returns violations hash with ok and violations keys" do
    result = described_class.new(
      reader: ->(key, ctnr, c) { Textus::Action::Get.new(key: key).call(container: ctnr, call: c) },
      manifest: store.container.manifest,
      audit_log: store.container.audit_log,
      schema_for: ->(name) { store.container.schemas.fetch_or_nil(name) },
    ).call(container: store.container, call: test_ctx)
    expect(result).to include("ok", "violations")
  end
end
