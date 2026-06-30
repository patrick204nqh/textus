# Cross-cutting write-verb behaviours, re-asserted today across put/delete/
# accept/reject/mv. Each shared example reads a small contract of `let`s the
# host group defines, so the verb specs stop hand-rolling the same probe.

# Asserts the action writes an audit row for `verb`. Host defines:
#   let(:store)   { ... }
#   let(:perform) { -> { store.with_role("automation").entry(:put, "feeds.foo", meta: {}, body: "x") } }
#
#   it_behaves_like "an audited write", "put"
# Asserts the action is refused for a canon-zone write when the role lacks the
# `author` capability. Host defines:
#   let(:store) { ... }
#   let(:canon_forbidden_action) { -> { store.with_role("automation").entry(:put, "knowledge.bar", …) } }
RSpec.shared_examples "a canon-write refused" do
  it "raises WriteForbidden when role lacks the capability the zone-kind requires" do
    expect { canon_forbidden_action.call }
      .to raise_error(
        Textus::WriteForbidden,
        /needs capability 'author'/,
      )
  end
end

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
