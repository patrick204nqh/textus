require "spec_helper"

# Proves the dogfood adr_index_reducer hook (ADR 0097): the reducer is loaded
# through the real Loader so it exercises the same code path as the live
# `.textus/hooks/` directory, and invoked through the RpcRegistry — the same
# surface every transform_rows reducer goes through at runtime.
RSpec.describe "adr_index_reducer" do
  let(:events) { Textus::Hooks::EventBus.new }
  let(:rpc)    { Textus::Hooks::RpcRegistry.new }
  # Minimal caps stub: only .rpc is required by transform_rows handlers.
  let(:caps)   { Struct.new(:rpc).new(rpc) }
  let(:rows) do
    [
      { "_key" => "knowledge.decisions.0001-first",
        "body" => "# ADR 0001 — First\n\n**Date:** 2025-01-01\n**Status:** Accepted\n" },
      { "_key" => "knowledge.decisions.0010-tenth",
        "body" => "# ADR 0010 — Tenth\n\n**Date:** 2025-02-02\n**Status:** Superseded by [ADR 0011](./0011-x.md)\n" },
    ]
  end

  before do
    # Load just the one hook file in isolation by copying it into a tmpdir so
    # other .textus/hooks/*.rb files do not register into this fresh registry.
    handler_path = File.expand_path("../../../.textus/hooks/adr_index_reducer.rb", __dir__)
    Dir.mktmpdir do |dir|
      FileUtils.cp(handler_path, File.join(dir, "adr_index_reducer.rb"))
      Textus::Hooks::Loader.new(events: events, rpc: rpc).load_dir(dir)
    end
  end

  it "registers an :adr_index_reducer transform_rows handler" do
    expect(rpc.names(:transform_rows)).to include(:adr_index_reducer)
  end

  it "parses number/title/date/status and sorts by number descending" do
    out = rpc.invoke(:transform_rows, :adr_index_reducer, rows: rows, caps: caps, config: {})
    adrs = out["adrs"]

    expect(adrs).to be_an(Array)
    expect(adrs.map { |a| a["number"] }).to eq(%w[0010 0001])
    expect(adrs.first["title"]).to eq("Tenth")
    expect(adrs.first["date"]).to eq("2025-02-02")
    expect(adrs.first["status"]).to start_with("Superseded")
  end

  it "parses the first-row ADR fields correctly" do
    out = rpc.invoke(:transform_rows, :adr_index_reducer, rows: rows, caps: caps, config: {})
    first_adr = out["adrs"].last # sorted descending: 0001 is last
    expect(first_adr["number"]).to eq("0001")
    expect(first_adr["title"]).to eq("First")
    expect(first_adr["date"]).to eq("2025-01-01")
    expect(first_adr["status"]).to eq("Accepted")
  end

  it "skips rows whose body does not match the ADR title pattern" do
    readme_row = { "_key" => "knowledge.decisions.README",
                   "body" => "# Architecture Decisions\n\nThis folder holds the ADR log.\n" }
    out = rpc.invoke(:transform_rows, :adr_index_reducer,
                     rows: [readme_row, rows.first], caps: caps, config: {})
    # Only the genuine ADR row should appear
    expect(out["adrs"].length).to eq(1)
    expect(out["adrs"].first["number"]).to eq("0001")
  end

  it "returns a hash with an 'adrs' key" do
    out = rpc.invoke(:transform_rows, :adr_index_reducer, rows: rows, caps: caps, config: {})
    expect(out).to be_a(Hash)
    expect(out).to have_key("adrs")
  end

  it "produces deterministic output (same input → same output)" do
    r1 = rpc.invoke(:transform_rows, :adr_index_reducer, rows: rows, caps: caps, config: {})
    r2 = rpc.invoke(:transform_rows, :adr_index_reducer, rows: rows, caps: caps, config: {})
    expect(r1).to eq(r2)
  end
end
