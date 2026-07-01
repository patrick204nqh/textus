require "spec_helper"

RSpec.describe "dispatch concern handlers" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "loads all use-case modules" do
    Textus::Dispatch::HandlerResolver.eager_load!

    handlers = Textus::Dispatch::HandlerResolver.discover_all
    names = handlers.map(&:name)

    expect(names).to include("Textus::UseCases::Read::GetEntry")
    expect(names).to include("Textus::UseCases::Write::PutEntry")
    expect(names).to include("Textus::UseCases::Ops::BootStore")
  end

  it "keeps read verbs reachable through the unified dispatch" do
    expect(store.list(prefix: "knowledge")).to be_an(Array)
  end
end
