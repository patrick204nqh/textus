require "spec_helper"
require "tmpdir"
require "fileutils"
require "time"

RSpec.describe "Pulse next_due_at" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/intake schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, write_policy: [runner] }
      entries:
        - key: intake.feed
          path: intake/feed.md
          zone: intake
          kind: intake
          intake:
            handler: noop
      rules:
        - { match: "intake.*", refresh: { ttl: 3600s, on_stale: warn } }
    YAML
    File.write(
      File.join(root, "zones/intake/feed.md"),
      "---\nkey: intake.feed\nlast_refreshed_at: \"#{Time.now.utc.iso8601}\"\n---\nhi\n",
    )
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }

  it "includes next_due_at: ISO-8601 string of the soonest-to-go-stale entry" do
    result = store.as("human").pulse(since: 0)
    expect(result["next_due_at"]).to be_a(String)
    expect { Time.parse(result["next_due_at"]) }.not_to raise_error
  end

  it "next_due_at is nil when no entries have a refresh policy with last_refreshed_at" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, write_policy: [runner] }
      entries:
        - key: intake.feed
          path: intake/feed.md
          zone: intake
          kind: intake
          intake:
            handler: noop
    YAML
    # Reinitialize store with fresh manifest (no rules)
    fresh_store = Textus::Store.new(root)
    result = fresh_store.as("human").pulse(since: 0)
    expect(result["next_due_at"]).to be_nil
  end
end
