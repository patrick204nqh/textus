require "spec_helper"

RSpec.describe "Textus::RoleScope#fetch_all (fetch_stale)" do
  let(:tmp) { Dir.mktmpdir }
  let(:textus) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(textus, "zones", "feeds"))
    FileUtils.mkdir_p(File.join(textus, "hooks"))

    File.write(File.join(textus, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: feeds, kind: quarantine }
      entries:
        - key: feeds.fresh
          kind: intake
          path: feeds/fresh.md
          zone: feeds
          intake:
            handler: counter
        - key: feeds.stale
          kind: intake
          path: feeds/stale.md
          zone: feeds
          intake:
            handler: counter
      rules:
        - match: feeds.fresh
          fetch:
            ttl: 1h
            on_stale: warn
        - match: feeds.stale
          fetch:
            ttl: 1s
            on_stale: warn
    YAML

    File.write(File.join(textus, "zones", "feeds", "fresh.md"), <<~MD)
      ---
      key: feeds.fresh
      last_fetched_at: "#{(Time.now - 60).utc.iso8601}"
      ---
      fresh
    MD

    File.write(File.join(textus, "zones", "feeds", "stale.md"), <<~MD)
      ---
      key: feeds.stale
      last_fetched_at: "2020-01-01T00:00:00Z"
      ---
      old
    MD

    File.write(File.join(textus, "hooks", "counter.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :counter) do |caps:, config:, args:|
          { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "fetched" }
        end
      end
    RUBY
  end

  after { FileUtils.remove_entry(tmp) }

  it "fetches every entry whose ttl has expired" do
    store = Textus::Store.new(textus)
    result = store.as("automation").fetch_all

    expect(result["ok"]).to be(true)
    expect(result["fetched"]).to eq(["feeds.stale"])
    expect(result["failed"]).to eq([])
  end
end
