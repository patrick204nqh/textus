# spec/conformance/steps/verb_registry_handler_spec.rb
require "spec_helper"

# Proves the dogfood verb_registry_handler step (ADR 0097): the handler is
# loaded through the real Loader so it exercises the same code path as the live
# `.textus/steps/` directory, and invoked through the RegistryStore — the
# same surface every intake handler goes through at runtime.
RSpec.describe "verb_registry_handler" do
  let(:registry) { Textus::Step::RegistryStore.new }
  # Minimal caps stub: only .rpc is required by resolve_handler handlers.
  let(:caps) { Struct.new(:rpc).new(registry) }

  before do
    # Load just the one step file in isolation by copying it into a tmpdir so
    # other .textus/steps/*.rb files do not register into this fresh registry.
    handler_path = File.expand_path("../../../.textus/steps/fetch/verbs.rb", __dir__)
    Dir.mktmpdir do |dir|
      steps_dir = File.join(dir, "steps")
      FileUtils.mkdir_p(File.join(steps_dir, "fetch"))
      FileUtils.cp(handler_path, File.join(steps_dir, "fetch", "verbs.rb"))
      Textus::Step::Loader.new(registry: registry).load_dir(steps_dir)
    end
  end

  it "registers a :verbs fetch handler" do
    expect(registry.names(:fetch)).to include(:verbs)
  end

  it "sources verbs from Read::Capabilities (no Dispatcher-internals reach)" do
    projected = Textus::Dispatch::Actions::Capabilities.new.call(container: nil, call: nil)["verbs"].map { |v| v["verb"] }.sort
    result = registry.invoke(:fetch, :verbs, caps: caps, config: {}, args: [])
    names = result["content"]["verbs"].map { |v| v["name"] }
    expect(names).to eq(projected)
    expect(result["content"]["verbs"].first.keys).to include("name", "summary")
  end

  it "has deterministic output (sorted by name)" do
    r1 = registry.invoke(:fetch, :verbs, caps: caps, config: {}, args: [])
    r2 = registry.invoke(:fetch, :verbs, caps: caps, config: {}, args: [])
    expect(r1["content"]["verbs"].map { |v| v["name"] })
      .to eq(r2["content"]["verbs"].map { |v| v["name"] })
  end
end
