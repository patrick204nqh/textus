require "spec_helper"

RSpec.describe Textus::Manifest::Schema do
  it "registers exactly the live rule fields (retention, not the retired policy field)" do
    expect(described_class::FIELD_REGISTRY.keys).to eq(%i[handler_permit guard retention react])
  end

  it "RULE_KEYS is match plus the live rule yaml_keys (retention included)" do
    expect(described_class::RULE_KEYS).to include("retention")
    expect(described_class::RULE_KEYS).to eq(%w[match handler_permit guard retention react])
  end

  it "ENTRY_KEYS includes source and excludes compute/template/intake" do
    expect(described_class::ENTRY_KEYS).to include("source")
    expect(described_class::ENTRY_KEYS).not_to include("compute", "template", "intake")
  end
end
