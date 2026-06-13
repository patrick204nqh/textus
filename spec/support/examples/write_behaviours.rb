# Cross-cutting write-verb behaviours, re-asserted today across put/delete/
# accept/reject/mv. Each shared example reads a small contract of `let`s the
# host group defines, so the verb specs stop hand-rolling the same probe.

# Asserts the action writes an audit row for `verb`. Host defines:
#   let(:store)   { ... }
#   let(:perform) { -> { store.as("automation").put("feeds.foo", meta: {}, body: "x") } }
#
#   it_behaves_like "an audited write", "put"
RSpec.shared_examples "an audited write" do |verb|
  it "records a #{verb.inspect} row in the audit log" do
    perform.call
    expect(store).to have_audit_verb(verb)
  end
end

# Asserts the action propagates the caller's correlation_id into the audit row.
# Host defines `store` and `perform_with_correlation` (a lambda that runs the
# action with correlation_id "corr-1"):
#
#   it_behaves_like "a correlated write", "put"
RSpec.shared_examples "a correlated write" do |verb|
  it "carries the correlation id onto the #{verb.inspect} audit row" do
    perform_with_correlation.call
    expect(store).to have_audit_verb(verb).with_correlation("corr-1")
  end
end

# Asserts the action is refused by the unified guard, naming the unmet
# predicate(s). Host defines `forbidden_action` (a lambda):
#
#   it_behaves_like "a guarded action", "author_held"
RSpec.shared_examples "a guarded action" do |*predicates|
  it "fails the guard naming #{predicates.inspect}" do
    expect { forbidden_action.call }.to fail_guard_with(*predicates)
  end
end

# Asserts the action fires `event_name` carrying the key and correlation id.
# Host defines `store`, `event_key`, and `emit` (a lambda running the action
# with correlation_id "corr-1"):
#
#   it_behaves_like "an event-emitting action", :entry_written
RSpec.shared_examples "an event-emitting action" do |event_name|
  it "fires #{event_name} with the key and correlation id" do
    seen = []
    store.steps.on(event_name, :spec_probe) do |ctx:, key:, **|
      seen << [event_name, key, ctx.correlation_id]
    end
    emit.call
    expect(seen).to include([event_name, event_key, "corr-1"])
  end
end
