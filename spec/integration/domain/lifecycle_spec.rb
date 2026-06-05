require "spec_helper"

RSpec.describe Textus::Domain::Lifecycle do
  include_context "textus_store_fixture"

  describe ".verdict (pure age decision)" do
    let(:policy) { Textus::Domain::Policy::Lifecycle.new(ttl: "30d", on_expire: "drop") }
    let(:now)    { Time.now }

    it "is not expired when the policy has no ttl" do
      no_ttl = Textus::Domain::Policy::Lifecycle.new(ttl: nil, on_expire: "drop")
      expect(described_class.verdict(policy: no_ttl, last_fetched_at: nil, mtime: now, now: now))
        .to eq([false, nil])
    end

    it "is expired when mtime is older than the ttl" do
      old = now - (40 * 86_400)
      expired, reason = described_class.verdict(policy: policy, last_fetched_at: nil, mtime: old, now: now)
      expect(expired).to be(true)
      expect(reason).to match(/ttl exceeded/)
    end

    it "lets last_fetched_at override mtime" do
      old_mtime = now - (40 * 86_400)
      fresh_fetch = (now - 86_400).iso8601
      expect(described_class.verdict(policy: policy, last_fetched_at: fresh_fetch, mtime: old_mtime, now: now))
        .to eq([false, nil])
    end
  end

  describe "#call (reporter)" do
    let(:store) do
      store_from_manifest(root, zones: %w[review], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: review, kind: canon }
        entries:
          - { key: review.oncall, path: review/oncall.md, zone: review, kind: leaf }
        rules:
          - match: "review.*"
            upkeep: { "on": stale, ttl: 30d, action: drop }
      YAML
    end

    let(:leaf) { File.join(root, "zones/review/oncall.md") }

    before do
      store
      File.write(leaf, "# oncall\n")
    end

    def report
      described_class.new(
        manifest: store.manifest,
        file_stat: Textus::Ports::Storage::FileStat.new,
        clock: Time,
      ).call
    end

    it "reports an aged leaf as expired with the policy's action" do
      aged = Time.now - (40 * 86_400)
      File.utime(aged, aged, leaf)
      row = report.find { |r| r["key"] == "review.oncall" }
      expect(row).not_to be_nil
      expect(row["expired"]).to be(true)
      expect(row["action"]).to eq("drop")
    end

    it "does not report a leaf younger than its ttl" do
      fresh = Time.now - 86_400
      File.utime(fresh, fresh, leaf)
      expect(report.find { |r| r["key"] == "review.oncall" }).to be_nil
    end
  end
end
