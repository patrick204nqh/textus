require "spec_helper"

RSpec.describe "correlation_id in audit rows" do
  include_context "textus_store_fixture"

  let(:store) { minimal_store(root) }

  it "put is audit-logged with the request's correlation_id" do
    store.as("human", correlation_id: "test-corr-put")
         .put("knowledge.foo", meta: { "name" => "foo" }, body: "hello")
    expect(store).to have_audit_verb("put").with_correlation("test-corr-put")
  end

  it "delete is audit-logged with the request's correlation_id" do
    ops = store.as("human", correlation_id: "test-corr-del")
    ops.put("knowledge.foo", meta: { "name" => "foo" }, body: "hello")
    ops.delete("knowledge.foo")
    expect(store).to have_audit_verb("delete").with_correlation("test-corr-del")
  end
end
