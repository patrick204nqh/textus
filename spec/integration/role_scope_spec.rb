require "spec_helper"

RSpec.describe Textus::Surfaces::RoleScope do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "Store#as(role) returns a RoleScope bound to that role" do
    scope = store.as("human")
    expect(scope).to be_a(Textus::Surfaces::RoleScope)
    expect(scope.role).to eq("human")
  end

  it "wires every Dispatcher verb as a Ruby method regardless of surfaces (ADR 0073)" do
    # Ruby is the implicit base API: RoleScope exposes every verb in-process,
    # independent of the contract's `surfaces` list (which only declares the
    # external CLI/MCP projections). A verb with empty surfaces is still
    # Ruby-callable — this is the property that lets `surfaces []` mean
    # "Ruby-only internal verb."
    scope = store.as("human")
    Textus::Dispatcher::VERBS.each_key do |verb|
      expect(scope).to respond_to(verb)
    end
  end

  it "Store#as(role).put writes and Store#as(role).get reads back" do
    result = store.as("human").put(
      "knowledge.foo",
      meta: { "name" => "foo" },
      body: "hello-rolescope",
    )
    expect(result).not_to be_nil

    env = store.as("human").get("knowledge.foo")
    expect(env).not_to be_nil
    expect(env.body.strip).to eq("hello-rolescope")
  end

  it "passes correlation_id: through to the audit record" do
    store.as("human", correlation_id: "test-corr-rolescope").put(
      "knowledge.foo",
      meta: { "name" => "foo" },
      body: "hi",
    )
    expect(store).to have_audit_verb("put").with_correlation("test-corr-rolescope")
  end

  it "#with_role returns a new RoleScope with the given role" do
    scope = store.as("human").with_role("automation")
    expect(scope).to be_a(Textus::Surfaces::RoleScope)
    expect(scope.role).to eq("automation")
  end

  it "#with_dry_run returns a RoleScope with dry_run=true" do
    scope = store.as("human").with_dry_run
    expect(scope).to be_a(Textus::Surfaces::RoleScope)
    expect(scope.dry_run?).to be(true)
  end

  it "Store#put delegates to the default role's RoleScope" do
    store.put("knowledge.foo", role: "human", meta: { "name" => "foo" }, body: "default")
    env = store.get("knowledge.foo")
    expect(env.body.strip).to eq("default")
  end

  describe "#dispatch_bound" do
    it "binds a by-name inputs hash once and invokes the verb" do
      env = store.as("human").dispatch_bound(:put, { key: "knowledge.foo", body: "hi" })
      expect(env.etag).to match(/\Asha256:/)
    end

    it "applies a declared around resource around dispatch_bound" do
      events = []
      resource_class = Class.new do
        def initialize(sink) = (@sink = sink)

        def wrap(scope:, inputs:, session:) # rubocop:disable Lint/UnusedMethodArgument
          @sink << :before
          result = yield(inputs)
          @sink << :after
          result
        end
      end
      Textus::Contract::Around.register(:spy_get, resource_class.new(events))
      allow(Textus::Dispatcher::VERBS[:get]).to receive(:contract).and_wrap_original do |m|
        m.call.with(around: :spy_get)
      end
      store.as("human").dispatch_bound(:get, { key: "knowledge.foo" })
      expect(events).to eq(%i[before after])
    end
  end
end
