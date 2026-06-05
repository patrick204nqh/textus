require "spec_helper"

RSpec.describe Textus::Write::Put do
  include_context "textus_store_fixture"

  let(:store) { quarantine_store(root) }

  # Contract for the cross-cutting write behaviours (audit row, correlation
  # propagation, event) shared from spec/support/examples/write_behaviours.rb.
  let(:perform) { -> { store.as("automation").put("feeds.foo", meta: {}, body: "x") } }
  let(:perform_with_correlation) do
    -> { store.as("automation", correlation_id: "corr-1").put("feeds.foo", meta: {}, body: "x") }
  end
  let(:emit)      { perform_with_correlation }
  let(:event_key) { "feeds.foo" }

  it "writes the envelope when role has permission" do
    envelope = store.as("automation").put(
      "feeds.foo", meta: { "key" => "feeds.foo" }, body: "hello"
    )
    expect(envelope.body || envelope.content).to include("hello")
    expect(File.exist?(File.join(root, "zones/feeds/foo.md"))).to be(true)
  end

  it "raises WriteForbidden when role lacks the capability the zone-kind requires" do
    # knowledge is a canon zone (needs the 'author' capability); automation
    # holds only [fetch, reconcile], so the write is genuinely refused.
    expect { store.as("automation").put("knowledge.bar", meta: {}, body: "x") }
      .to raise_error(
        Textus::WriteForbidden,
        /writing 'knowledge.bar' \(zone 'knowledge'\) needs capability 'author'/,
      )
  end

  it "refuses a forbidden role with write_forbidden via the unified guard (zone_writable_by)" do
    expect { store.as("automation").put("knowledge.bar", meta: {}, body: "x") }
      .to raise_error(Textus::WriteForbidden) { |e| expect(e.code).to eq("write_forbidden") }
  end

  it_behaves_like "an audited write", "put"
  it_behaves_like "a correlated write", "put"
  it_behaves_like "an event-emitting action", :entry_put
end
