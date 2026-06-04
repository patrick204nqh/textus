require "spec_helper"

RSpec.describe Textus::Write::Delete do
  include_context "textus_store_fixture"

  let!(:store) { quarantine_store(root) }

  it "removes the entry file and fires :deleted with correlation_id" do
    File.write(File.join(root, "zones", "feeds", "foo.md"), "---\nkey: feeds.foo\n---\nbody\n")

    events = []
    store.events.register(:entry_deleted, :capture) do |ctx:, key:, **|
      events << [:entry_deleted, key, ctx.correlation_id]
    end

    store.as("automation", correlation_id: "del-1").delete("feeds.foo")

    expect(File.exist?(File.join(root, "zones", "feeds", "foo.md"))).to be(false)
    expect(events).to include([:entry_deleted, "feeds.foo", "del-1"])
  end

  it "raises WriteForbidden when role lacks the capability the zone-kind requires" do
    File.write(File.join(root, "zones", "knowledge", "bar.md"), "---\nkey: knowledge.bar\n---\nbody\n")

    # knowledge is a canon zone (needs the 'author' capability); automation
    # holds only [fetch, build], so the delete is genuinely refused.
    expect do
      store.as("automation").delete("knowledge.bar")
    end.to raise_error(
      Textus::WriteForbidden,
      /writing 'knowledge.bar' \(zone 'knowledge'\) needs capability 'author'/,
    )
  end
end
