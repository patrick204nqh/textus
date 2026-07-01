require "spec_helper"

RSpec.describe "dispatch concern handlers" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "loads read, write, and maintenance handlers" do
    Textus::Dispatch::HandlerResolver.eager_load!

    handlers = Textus::Dispatch::HandlerResolver.discover_all
    names = handlers.map(&:name)

    expect(names).to include("Textus::Dispatch::Handlers::ReadHandler")
    expect(names).to include("Textus::Dispatch::Handlers::WriteHandler")
    expect(names).to include("Textus::Dispatch::Handlers::MaintenanceHandler")
  end

  it "keeps read verbs reachable through the read concern handler" do
    expect(store.entry(:list, prefix: "knowledge")).to be_an(Array)
  end
end
