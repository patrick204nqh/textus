require "spec_helper"

RSpec.describe Textus::RoleScope do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "Store#as(role) returns a RoleScope bound to that role" do
    scope = store.as("human")
    expect(scope).to be_a(Textus::RoleScope)
    expect(scope.role).to eq("human")
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
    expect(scope).to be_a(Textus::RoleScope)
    expect(scope.role).to eq("automation")
  end

  it "#with_dry_run returns a RoleScope with dry_run=true" do
    scope = store.as("human").with_dry_run
    expect(scope).to be_a(Textus::RoleScope)
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
  end

  it "injects contract literal-defaults for absent kwargs so the get verb is read-through (ADR 0062 amendment)" do
    # store.as(role).get(key) must pass fetch: true (read-through) even though
    # the method default is fetch: false (the safe default for direct callers).
    captured = nil
    allow(Textus::Read::Get).to receive(:new).and_wrap_original do |orig, **kw|
      inst = orig.call(**kw)
      allow(inst).to receive(:call).and_wrap_original do |m, *a, **k|
        captured = k
        m.call(*a, **k)
      end
      inst
    end
    store.as("human").get("knowledge.foo")
    expect(captured).to eq({ fetch: true })
  end
end
