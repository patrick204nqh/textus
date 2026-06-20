require "spec_helper"

RSpec.describe "build verb removed (ADR 0087)" do
  it "is absent from the dispatcher" do
    expect(Textus::Action::VERBS).not_to have_key(:build)
  end

  it "is absent from the MCP catalog names" do
    expect(Textus::Surface::MCP::Catalog.names).not_to include("build")
  end

  it "is absent from the MCP catalog write_verbs" do
    expect(Textus::Surface::MCP::Catalog.write_verbs).not_to include("build")
  end

  it "exposes drain in the dispatcher" do
    expect(Textus::Action::VERBS).to have_key(:drain)
  end

  it "does not expose tend in the dispatcher" do
    expect(Textus::Action::VERBS).not_to have_key(:tend)
  end
end
