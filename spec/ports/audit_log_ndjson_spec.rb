require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"

RSpec.describe Textus::Ports::AuditLog do
  let(:tmp) { Dir.mktmpdir }
  let(:log) { described_class.new(tmp) }

  after { FileUtils.remove_entry(tmp) }

  it "writes one valid JSON object per line" do
    log.append(role: "human", verb: "put", key: "working.x", etag_before: nil, etag_after: "sha256:abc")
    raw = File.read(File.join(tmp, "audit.log"))
    expect(raw.lines.length).to eq(1)
    parsed = JSON.parse(raw.lines.first)
    expect(parsed).to include(
      "role" => "human", "verb" => "put", "key" => "working.x",
      "etag_before" => nil, "etag_after" => "sha256:abc"
    )
    expect(parsed["ts"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    expect(parsed).not_to have_key("extras")
  end

  it "carries extras as a sub-object when present" do
    log.append(
      role: "runner", verb: "event_error", key: "-",
      etag_before: nil, etag_after: nil,
      extras: { "event" => "put", "hook" => "h", "error" => "boom" }
    )
    parsed = JSON.parse(File.read(File.join(tmp, "audit.log")).lines.first)
    expect(parsed["extras"]).to eq("event" => "put", "hook" => "h", "error" => "boom")
  end

  it "omits extras when empty hash is passed" do
    log.append(role: "human", verb: "put", key: "x", etag_before: nil, etag_after: nil, extras: {})
    parsed = JSON.parse(File.read(File.join(tmp, "audit.log")).lines.first)
    expect(parsed).not_to have_key("extras")
  end

  it "promotes from_key/to_key/uid to top level and removes them from extras" do
    log.append(
      role: "human", verb: "mv", key: "working.notes.beta",
      etag_before: "sha256:old", etag_after: "sha256:new",
      extras: {
        "from_key" => "working.notes.alpha", "to_key" => "working.notes.beta",
        "from_path" => "/a/alpha.md", "to_path" => "/a/beta.md",
        "uid" => "abc123"
      }
    )
    parsed = JSON.parse(File.read(File.join(tmp, "audit.log")).lines.first)
    expect(parsed["from_key"]).to eq("working.notes.alpha")
    expect(parsed["to_key"]).to eq("working.notes.beta")
    expect(parsed["uid"]).to eq("abc123")
    # from_path/to_path remain in extras (not in the promotion list)
    expect(parsed["extras"]).to include("from_path" => "/a/alpha.md", "to_path" => "/a/beta.md")
    # promoted keys must NOT appear inside extras
    expect(parsed["extras"]).not_to have_key("from_key")
    expect(parsed["extras"]).not_to have_key("to_key")
    expect(parsed["extras"]).not_to have_key("uid")
  end

  describe "#last_writer_for" do
    it "returns the role of the last writer for a key (NDJSON lines)" do
      log.append(role: "agent", verb: "put", key: "x", etag_before: nil, etag_after: "e1")
      log.append(role: "human", verb: "put", key: "x", etag_before: "e1", etag_after: "e2")
      log.append(role: "agent", verb: "put", key: "y", etag_before: nil, etag_after: "e3")
      expect(log.last_writer_for("x")).to eq("human")
    end
  end
end
