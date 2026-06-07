require "spec_helper"
require "time"

RSpec.describe "Pulse next_due_at" do
  include_context "textus_store_fixture"

  before do
    %w[zones/intake schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, kind: machine }
      entries:
        - key: intake.feed
          path: intake/feed.md
          zone: intake
          kind: produced
          source:
            from: handler
            handler: noop
            ttl: 3600s
    YAML
    File.write(
      File.join(root, "zones/intake/feed.md"),
      "---\nkey: intake.feed\nlast_fetched_at: \"#{Time.now.utc.iso8601}\"\n---\nhi\n",
    )
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }

  it "includes next_due_at: ISO-8601 string of the soonest-to-go-stale entry" do
    result = store.as("human").pulse(since: 0)
    expect(result["next_due_at"]).to be_a(String)
    expect { Time.parse(result["next_due_at"]) }.not_to raise_error
  end

  it "next_due_at is nil when no entries have a fetch policy with last_fetched_at" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, kind: machine }
      entries:
        - key: intake.feed
          path: intake/feed.md
          zone: intake
          kind: produced
          source:
            from: handler
            handler: noop
    YAML
    # Reinitialize store with fresh manifest (no rules)
    fresh_store = Textus::Store.new(root)
    result = fresh_store.as("human").pulse(since: 0)
    expect(result["next_due_at"]).to be_nil
  end
end
