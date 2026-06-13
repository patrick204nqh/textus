require "spec_helper"

RSpec.describe Textus::Write::KeyDelete do
  include_context "textus_store_fixture"

  let!(:store) { machine_store(root) }
  # Contract for the cross-cutting write behaviours (spec/support/examples).
  let(:perform) { -> { store.as("automation").key_delete("feeds.foo") } }
  let(:perform_with_correlation) { -> { store.as("automation", correlation_id: "corr-1").key_delete("feeds.foo") } }
  let(:emit)      { perform_with_correlation }
  let(:event_key) { "feeds.foo" }

  # The entry must exist on disk before it can be deleted.
  before { File.write(File.join(root, "data", "feeds", "foo.md"), "---\nkey: feeds.foo\n---\nbody\n") }

  it_behaves_like "an audited write", "key_delete"
  it_behaves_like "a correlated write", "key_delete"
  it_behaves_like "an event-emitting action", :entry_deleted

  it "removes the entry file from disk" do
    expect { perform.call }.to change { File.exist?(File.join(root, "data", "feeds", "foo.md")) }.from(true).to(false)
  end

  it "raises WriteForbidden when role lacks the capability the zone-kind requires" do
    File.write(File.join(root, "data", "knowledge", "bar.md"), "---\nkey: knowledge.bar\n---\nbody\n")

    # knowledge is a canon zone (needs the 'author' capability); automation
    # holds only [converge], so the delete is genuinely refused.
    expect do
      store.as("automation").key_delete("knowledge.bar")
    end.to raise_error(
      Textus::WriteForbidden,
      /writing 'knowledge.bar' \(zone 'knowledge'\) needs capability 'author'/,
    )
  end
end
