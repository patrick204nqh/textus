require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe Textus::Read::Pulse do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/review"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [accept, propose] }
        - { name: agent, can: [propose] }
      zones:
        - { name: working, kind: canon }
        - { name: review,  kind: queue }
      entries: []
    YAML
  end

  let(:store) { Textus::Store.new(root) }
  let(:ops)   { store.as("human") }

  it "returns an envelope with cursor, changed, stale, pending_review, doctor" do
    result = ops.pulse(since: 0)
    expect(result).to include("cursor", "changed", "stale", "pending_review", "doctor")
    expect(result["doctor"]).to include("ok", "warn", "fail")
  end

  it "advances cursor monotonically across calls" do
    store.audit_log.append(role: "human", verb: "put", key: "a", etag_before: nil, etag_after: "e1")
    c1 = ops.pulse(since: 0)["cursor"]

    store.audit_log.append(role: "human", verb: "put", key: "b", etag_before: nil, etag_after: "e2")
    c2 = ops.pulse(since: c1)["cursor"]

    expect(c2).to be > c1
  end

  it "returns empty changed[] when nothing happened since cursor" do
    store.audit_log.append(role: "human", verb: "put", key: "a", etag_before: nil, etag_after: "e1")
    cursor_now = store.audit_log.latest_seq

    result = ops.pulse(since: cursor_now)
    expect(result["cursor"]).to eq(cursor_now)
    expect(result["changed"]).to eq([])
  end

  it "returns changed rows with seq > since" do
    store.audit_log.append(role: "human", verb: "put", key: "a", etag_before: nil, etag_after: "e1")
    baseline = store.audit_log.latest_seq
    store.audit_log.append(role: "human", verb: "put", key: "b", etag_before: nil, etag_after: "e2")

    result = ops.pulse(since: baseline)
    expect(result["changed"].map { |r| r["key"] }).to eq(["b"])
  end

  it "raises CursorExpired when since is below min_available_seq" do
    File.write(File.join(root, "audit.log.1.meta.json"),
               JSON.generate({ "min_seq" => 50, "max_seq" => 100, "rotated_at" => Time.now.utc.iso8601 }))
    File.write(File.join(root, "audit.log.1"), "")
    store.audit_log.append(role: "human", verb: "put", key: "a", etag_before: nil, etag_after: "e1")

    expect { ops.pulse(since: 10) }.to raise_error(Textus::CursorExpired)
  end
end
