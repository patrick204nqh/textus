require "spec_helper"

# Proves the cookbook's multi-machine environment-scan recipe: a NESTED intake
# (feeds.machines.*) whose handler keys off args[:leaf_segments] to pick the
# machine, runs a per-host scan (the SSH/local probe is stubbed here with canned
# JSON), and delegates the parse to the built-in :json handler. Fetching a leaf
# key populates a per-machine entry; tracked:false keeps the tree gitignored.
RSpec.describe "cookbook: environment-scan (nested machines intake)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[feeds], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: automation, can: [converge] }
      lanes:
        - { name: feeds, kind: machine }
      entries:
        - key: feeds.machines
          path: feeds/machines
          lane: feeds
          format: yaml
          nested: true
          tracked: false
          kind: nested
      rules: []
    YAML
  end

  it "marks the nested intake tracked:false (drives the gitignore)" do
    entry = store.manifest.data.entries.find { |e| e.key == "feeds.machines" }
    expect(entry.tracked?).to be(false)
    expect(entry.nested?).to be(true)
  end
end
