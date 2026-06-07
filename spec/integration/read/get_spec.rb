require "spec_helper"
require "time"

RSpec.describe Textus::Read::Get do
  include_context "textus_store_fixture"

  # Builds an intake store inline (no `intake_store` fixture dependency).
  # The hook file must exist so the manifest loads; the file's mtime is used
  # as the staleness basis when last_fetched_at is absent from the envelope.
  def intake_hook_rb
    "Textus.hook { |reg| reg.on(:resolve_handler, :test_intake) { |**| { body: \"x\" } } }\n"
  end

  def build_store_with_intake(ttl:, zone: "knowledge")
    store_from_manifest(root,
                        zones: [zone],
                        files: { "hooks/test_intake.rb" => intake_hook_rb },
                        manifest: <<~YAML)
                          version: textus/3
                          zones:
                            - { name: #{zone}, kind: canon }
                          entries:
                            - key: #{zone}.doc
                              kind: intake
                              path: #{zone}/doc.md
                              zone: #{zone}
                              source: { from: handler, handler: test_intake, ttl: #{ttl} }
                        YAML
  end

  def build_store_no_intake
    minimal_store(root, kind_zone: "machine", key: "feeds.doc", path: "feeds/doc.md")
  end

  def write_doc(zone: "knowledge", last_fetched_at: nil)
    meta_line = last_fetched_at ? "last_fetched_at: '#{last_fetched_at}'" : "name: doc"
    File.write(File.join(root, "zones", zone, "doc.md"), <<~MD)
      ---
      #{meta_line}
      ---
      stored body
    MD
  end

  # get is a pure read (ADR 0089, 0093): it annotates freshness but NEVER ingests.

  it "returns the on-disk envelope, observing staleness without ingesting" do
    store = build_store_with_intake(ttl: "1s")
    write_doc(last_fetched_at: "2020-01-01T00:00:00Z")
    leaf = File.join(root, "zones", "knowledge", "doc.md")
    before = File.read(leaf)
    ctx = test_ctx(role: "automation")

    env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")

    expect(env).not_to be_nil
    expect(env.freshness.stale).to be(true)    # observed stale, NOT refreshed
    expect(env.freshness.fetching).to be(false)
    expect(File.read(leaf)).to eq(before)      # the stale read wrote nothing
  end

  it "returns nil when the key has no envelope" do
    store = build_store_with_intake(ttl: "1h")
    ctx = test_ctx(role: "automation")
    use_case = described_class.new(container: store.container, call: ctx)

    expect(use_case.call("knowledge.doc")).to be_nil
  end

  it "annotates as fresh when no source.ttl applies (non-intake leaf)" do
    store = build_store_no_intake
    File.write(File.join(root, "zones", "feeds", "doc.md"), "---\nname: doc\n---\nbody\n")
    call = Textus::Call.build(role: "automation")
    env = described_class.new(container: store.container, call: call).call("feeds.doc")
    expect(env.freshness.stale).to be(false)
    expect(env.freshness.fetching).to be(false)
  end

  it "annotates as fresh when the envelope is within TTL" do
    store = build_store_with_intake(ttl: "1h")
    write_doc(last_fetched_at: Time.now.utc.iso8601)
    ctx = test_ctx(role: "automation")
    env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")
    expect(env.freshness.stale).to be(false)
  end

  it "annotates as stale when past TTL (still does NOT ingest)" do
    store = build_store_with_intake(ttl: "1s")
    write_doc(last_fetched_at: "2020-01-01T00:00:00Z")
    ctx = test_ctx(role: "automation")
    env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")
    expect(env.freshness.stale).to be(true)
    expect(env.freshness.fetching).to be(false)
  end

  it "uses file mtime as basis when last_fetched_at is absent" do
    store = build_store_with_intake(ttl: "1s")
    write_doc # no last_fetched_at
    leaf = File.join(root, "zones", "knowledge", "doc.md")
    aged = Time.now - 10
    File.utime(aged, aged, leaf)
    ctx = test_ctx(role: "automation")
    env = described_class.new(container: store.container, call: ctx).call("knowledge.doc")
    expect(env.freshness.stale).to be(true)
  end
end
