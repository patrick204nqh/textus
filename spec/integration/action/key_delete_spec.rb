require "spec_helper"

RSpec.describe Textus::Action::KeyDelete do
  include_context "textus_store_fixture"

  let!(:store) { machine_store(root) }
  let(:canon_forbidden_action) do
    lambda {
      File.write(File.join(root, "data", "knowledge", "bar.md"), "---\nkey: knowledge.bar\n---\nbody\n")
      store.as("automation").key_delete("knowledge.bar")
    }
  end
  # Contract for the cross-cutting write behaviours (spec/support/examples).
  let(:perform) { -> { store.as("automation").key_delete("feeds.foo") } }
  let(:perform_with_correlation) { -> { store.as("automation", correlation_id: "corr-1").key_delete("feeds.foo") } }

  # The entry must exist on disk before it can be deleted.
  before { File.write(File.join(root, "data", "feeds", "foo.md"), "---\nkey: feeds.foo\n---\nbody\n") }

  it_behaves_like "an audited write", "key_delete"
  it_behaves_like "a correlated write", "key_delete"

  it "removes the entry file from disk" do
    expect { perform.call }.to change { File.exist?(File.join(root, "data", "feeds", "foo.md")) }.from(true).to(false)
  end

  it_behaves_like "a canon-write refused"
end
