require "spec_helper"

RSpec.describe Textus::Write::Delete do
  include_context "textus_store_fixture"

  let(:store) { quarantine_store(root) }

  it "removes the entry file and fires :deleted with correlation_id" do
    store # ensure zone dirs exist before writing seed file
    File.write(File.join(root, "zones", "working", "foo.md"), "---\nkey: working.foo\n---\nbody\n")

    events = []
    store.events.register(:entry_deleted, :capture) do |ctx:, key:, **|
      events << [:entry_deleted, key, ctx.correlation_id]
    end

    store.as("automation", correlation_id: "del-1").delete("working.foo")

    expect(File.exist?(File.join(root, "zones", "working", "foo.md"))).to be(false)
    expect(events).to include([:entry_deleted, "working.foo", "del-1"])
  end

  it "raises WriteForbidden when role lacks the capability the zone-kind requires" do
    store # ensure zone dirs exist before writing seed file
    File.write(File.join(root, "zones", "identity", "bar.md"), "---\nkey: identity.bar\n---\nbody\n")

    # identity is a canon zone (needs the 'author' capability); automation
    # holds only [fetch, build], so the delete is genuinely refused.
    expect do
      store.as("automation").delete("identity.bar")
    end.to raise_error(
      Textus::WriteForbidden,
      /writing 'identity.bar' \(zone 'identity'\) needs capability 'author'/,
    )
  end
end
