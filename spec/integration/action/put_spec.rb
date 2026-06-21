require "spec_helper"

RSpec.describe Textus::Action::Put do
  include_context "textus_store_fixture"

  let(:store) { machine_store(root) }

  # Contract for the cross-cutting write behaviours (audit row, correlation
  # propagation, event) shared from spec/support/examples/write_behaviours.rb.
  let(:perform) { -> { store.as("automation").put("feeds.foo", meta: {}, body: "x") } }
  let(:perform_with_correlation) do
    -> { store.as("automation", correlation_id: "corr-1").put("feeds.foo", meta: {}, body: "x") }
  end

  it "writes the envelope when role has permission" do
    envelope = store.as("automation").put(
      "feeds.foo", meta: { "key" => "feeds.foo" }, body: "hello"
    )
    expect(envelope.body || envelope.content).to include("hello")
    expect(File.exist?(File.join(root, "data/feeds/foo.md"))).to be(true)
  end

  let(:canon_forbidden_action) { -> { store.as("automation").put("knowledge.bar", meta: {}, body: "x") } }

  it_behaves_like "a canon-write refused"

  it "refuses a forbidden role with write_forbidden via the unified guard (zone_writable_by)" do
    expect { canon_forbidden_action.call }
      .to raise_error(Textus::WriteForbidden) { |e| expect(e.code).to eq("write_forbidden") }
  end

  it_behaves_like "an audited write", "put"
  it_behaves_like "a correlated write", "put"
end
