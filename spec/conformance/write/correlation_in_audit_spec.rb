require "spec_helper"

RSpec.describe "correlation_id in audit rows" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "put is audit-logged with the request's correlation_id" do
    store.with_role("human").with_correlation_id("test-corr-put")
         .entry(:put, "knowledge.foo", meta: { "name" => "foo" }, body: "hello")
    expect(store).to have_audit_verb("put").with_correlation("test-corr-put")
  end

  it "delete is audit-logged with the request's correlation_id" do
    ops = store.with_role("human").with_correlation_id("test-corr-del")
    ops.entry(:put, "knowledge.foo", meta: { "name" => "foo" }, body: "hello")
    ops.entry(:key_delete, "knowledge.foo")
    expect(store).to have_audit_verb("key_delete").with_correlation("test-corr-del")
  end
end
