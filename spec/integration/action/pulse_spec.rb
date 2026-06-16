require "spec_helper"

RSpec.describe Textus::Action::Pulse do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/proposals"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: proposals,  kind: queue }
      entries: []
    YAML
  end

  let(:store) { Textus::Store.new(root) }
  let(:ops)   { store.as("human") }

  it "returns cursor, changed, pending_review, contract_etag, index_etag" do
    result = ops.pulse(since: 0)
    expect(result).to include("cursor", "changed", "pending_review", "contract_etag", "index_etag")
    expect(result).not_to have_key("stale")
    expect(result).not_to have_key("doctor")
    expect(result).not_to have_key("next_due_at")
  end

  it "index_etag is nil when artifacts.index does not exist" do
    result = ops.pulse(since: 0)
    expect(result["index_etag"]).to be_nil
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
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(File.join(audit_dir_path(root), "audit.log.1.meta.json"),
               JSON.generate({ "min_seq" => 50, "max_seq" => 100, "rotated_at" => Time.now.utc.iso8601 }))
    File.write(File.join(audit_dir_path(root), "audit.log.1"), "")
    store.audit_log.append(role: "human", verb: "put", key: "a", etag_before: nil, etag_after: "e1")

    expect { ops.pulse(since: 10) }.to raise_error(Textus::CursorExpired)
  end
end
