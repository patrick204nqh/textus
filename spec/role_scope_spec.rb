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
end
