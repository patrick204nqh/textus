require "spec_helper"

# Guard (ADR 0037): each write-flow template is keyed by a capability. If a
# capability is renamed in the LANES table (Manifest::Schema), a stale template
# key silently orphans — the verb just drops out of write_flows with no error.
# This pins the template keys to the capability vocabulary so a rename fails here.
RSpec.describe "Boot::WRITE_FLOW_TEMPLATES keys track the capability vocabulary (ADR 0037)" do
  let(:template_keys) { Textus::Boot::WRITE_FLOW_TEMPLATES.keys.map(&:to_s).sort }
  let(:capabilities)  { Textus::Manifest::Schema::CAPABILITIES.map(&:to_s).sort }

  it "has a template for every capability and no template for a non-capability" do
    msg = "write-flow templates #{template_keys.inspect} != capabilities #{capabilities.inspect}"
    expect(template_keys).to eq(capabilities), msg
  end
end
