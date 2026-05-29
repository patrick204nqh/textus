require "spec_helper"
require "fileutils"
require "tmpdir"

# Proves that IntakeCheck TTL comparison uses the injected clock port rather
# than wall-clock Time.now. A fake clock is advanced to a deterministic
# position, eliminating any dependence on the system clock or sleep.
RSpec.describe "Textus::Domain::Staleness IntakeCheck with fake clock" do
  include_context "textus_store_fixture"

  # Builds a manifest + file on disk with an intake entry whose
  # last_refreshed_at is fixed in the past. The fake clock is then advanced to
  # a position where the TTL is definitely exceeded, proving the IntakeCheck
  # comparison uses the injected clock rather than wall-clock Time.now.
  def build_intake_fixture!(last_refreshed_at_str)
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, write_policy: [runner] }
      entries:
        - key: intake.feed
          kind: intake
          path: intake/feed.md
          zone: intake
          intake: { handler: stub }
      rules:
        - match: intake.feed
          refresh:
            ttl: 1h
            on_stale: warn
    YAML
    File.write(File.join(root, "zones/intake/feed.md"), <<~MD)
      ---
      last_refreshed_at: "#{last_refreshed_at_str}"
      ---
      body
    MD
  end

  it "reports ttl exceeded when fake clock is advanced past the TTL window" do
    refreshed_at = Time.utc(2020, 6, 1, 12, 0, 0)
    build_intake_fixture!(refreshed_at.iso8601)

    store    = Textus::Store.new(root)
    manifest = store.manifest

    # Fake clock whose #now returns a time 2 hours after last_refreshed_at.
    # TTL is 1h (3600s), so (now - last) = 7200 > 3600 → stale.
    fake_clock = Object.new
    fake_clock.define_singleton_method(:now) { Time.utc(2020, 6, 1, 14, 0, 0) }

    rows = Textus::Domain::Staleness.new(
      manifest: manifest,
      file_stat: Textus::Ports::Storage::FileStat.new,
      clock: fake_clock,
    ).call

    expect(rows.length).to eq(1)
    expect(rows.first["key"]).to eq("intake.feed")
    expect(rows.first["reason"]).to match(/ttl exceeded/)
  end

  it "reports NOT stale when fake clock is within the TTL window" do
    refreshed_at = Time.utc(2020, 6, 1, 12, 0, 0)
    build_intake_fixture!(refreshed_at.iso8601)

    store    = Textus::Store.new(root)
    manifest = store.manifest

    # Fake clock returns a time only 30 minutes after last_refreshed_at.
    # TTL is 1h (3600s), so (now - last) = 1800 < 3600 → not stale.
    fake_clock = Object.new
    fake_clock.define_singleton_method(:now) { Time.utc(2020, 6, 1, 12, 30, 0) }

    rows = Textus::Domain::Staleness.new(
      manifest: manifest,
      file_stat: Textus::Ports::Storage::FileStat.new,
      clock: fake_clock,
    ).call

    expect(rows).to eq([])
  end
end
