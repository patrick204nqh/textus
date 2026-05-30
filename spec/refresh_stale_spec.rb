require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Textus::RoleScope#refresh_all (refresh_stale)" do
  let(:tmp) { Dir.mktmpdir }
  let(:textus) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(textus, "zones", "working"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: quarantine }
      entries:
        - key: working.fresh
          kind: intake
          path: working/fresh.md
          zone: working
          intake:
            handler: counter
        - key: working.stale
          kind: intake
          path: working/stale.md
          zone: working
          intake:
            handler: counter
      rules:
        - match: working.fresh
          refresh:
            ttl: 1h
            on_stale: warn
        - match: working.stale
          refresh:
            ttl: 1s
            on_stale: warn
    YAML

    File.write(File.join(textus, "zones", "working", "fresh.md"), <<~MD)
      ---
      key: working.fresh
      last_refreshed_at: "#{(Time.now - 60).utc.iso8601}"
      ---
      fresh
    MD

    File.write(File.join(textus, "zones", "working", "stale.md"), <<~MD)
      ---
      key: working.stale
      last_refreshed_at: "2020-01-01T00:00:00Z"
      ---
      old
    MD

    File.write(File.join(textus, "hooks", "counter.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :counter) do |caps:, config:, args:|
          { _meta: { "last_refreshed_at" => Time.now.utc.iso8601 }, body: "refreshed" }
        end
      end
    RUBY
  end

  after { FileUtils.remove_entry(tmp) }

  it "refreshes every entry whose ttl has expired" do
    store = Textus::Store.new(textus)
    result = store.as("automation").refresh_all

    expect(result["ok"]).to be(true)
    expect(result["refreshed"]).to eq(["working.stale"])
    expect(result["failed"]).to eq([])
  end
end
