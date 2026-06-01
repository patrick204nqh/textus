require "spec_helper"

# Proves the cookbook's multi-machine environment-scan recipe: a NESTED intake
# (feeds.machines.*) whose handler keys off args[:leaf_segments] to pick the
# machine, runs a per-host scan (the SSH/local probe is stubbed here with canned
# JSON), and delegates the parse to the built-in :json handler. Fetching a leaf
# key populates a per-machine entry; tracked:false keeps the tree gitignored.
RSpec.describe "cookbook: environment-scan (nested machines intake)" do
  include_context "textus_store_fixture"

  # Canned probe output stands in for `ssh host '<probe script>'`. A mapping
  # (object), so a format:yaml entry stores queryable content.
  let(:probe_json) { %({"os":"darwin24","packages":{"brew":42},"runtimes":{"ruby":"3.3.9","node":"20.11"}}) }

  let(:hook) { <<~RUBY }
    Textus.hook do |reg|
      reg.on(:resolve_intake, :machines) do |caps:, config:, args:|
        machine = args[:leaf_segments].first
        raise "unknown machine: \#{machine}" unless config.fetch("machines").key?(machine)
        raw = #{probe_json.inspect}                      # stands in for the SSH probe
        caps.rpc.invoke(:resolve_intake, :json,
                        caps: caps, config: { "bytes" => raw }, args: args)
      end
    end
  RUBY

  let(:store) do
    store_from_manifest(root, zones: %w[feeds], files: { "hooks/machines.rb" => hook }, manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: automation, can: [fetch] }
      zones:
        - { name: feeds, kind: quarantine }
      entries:
        - key: feeds.machines
          path: feeds/machines
          zone: feeds
          format: yaml
          nested: true
          tracked: false
          kind: intake
          intake:
            handler: machines
            config:
              machines:
                laptop:   { via: local }
                prod-web: { via: ssh, host: "user@10.0.0.5" }
      rules:
        - match: feeds.machines.**
          fetch: { ttl: 1h, on_stale: warn }
    YAML
  end

  it "fans out per machine: fetching a leaf yields that host's parsed snapshot" do
    store.as("automation").fetch("feeds.machines.prod-web")
    env = store.as("automation").get("feeds.machines.prod-web")

    expect(env.content["os"]).to eq("darwin24")
    expect(env.content["packages"]).to eq("brew" => 42)
    expect(env.content["runtimes"]).to eq("ruby" => "3.3.9", "node" => "20.11")
  end

  it "marks the nested intake tracked:false (drives the gitignore)" do
    entry = store.manifest.data.entries.find { |e| e.key == "feeds.machines" }
    expect(entry.tracked?).to be(false)
    expect(entry.nested?).to be(true)
  end
end
