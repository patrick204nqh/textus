require "spec_helper"

# Three-layer sandwich architecture (ADR 0106, extended by 2026-07-03 redesign):
#
#   Layer 0: infra/       — FileStore, Database, Clock, Locks
#   Layer 1: protocol/    — Gate, Envelope, Audit, Index, Key, Links, Format,
#                           Schema, Layout, Manifest, Async, Lane
#   Layer 2: lanes        — human/, agent/, ingest/, artifact/, workflow/
#   Layer 3: surface/     — CLI, MCP
#
# Protocol must never reach up into lanes or surfaces.
# Lanes must never reach sideways into other lanes.

layers_above_protocol = %w[Human Agent Ingest Artifact Surface CLI MCP]

RSpec.describe "layering invariant" do
  def protocol_files
    Dir[File.expand_path("../../../lib/textus/protocol/**/*.rb", __dir__)]
  end

  it "has protocol files to check (guard is wired to a real tree)" do
    expect(protocol_files).not_to be_empty
  end

  layers_above_protocol.each do |layer|
    it "protocol/ never references Textus::#{layer}::" do
      offenders = protocol_files.select { |f| File.read(f).match?(/\bTextus::#{layer}::/) }
      expect(offenders).to be_empty,
                           "lib/textus/protocol reaches up into Textus::#{layer}:: in:\n  " \
                           "#{offenders.map { |f| f.sub(%r{.*/lib/}, "lib/") }.join("\n  ")}\n" \
                           "Protocol is Layer 1 — it must not know about upper layers."
    end
  end

  downward_forbidden = [
    { from: "dispatch", must_not_import: %w[Surface CLI MCP] },
    { from: "manifest", must_not_import: %w[Surface Dispatch UseCases] },
    { from: "protocol", must_not_import: %w[Surface Human Agent Ingest Artifact] },
  ]

  downward_forbidden.each do |rule|
    layer_files = Dir["lib/textus/#{rule[:from]}/**/*.rb"]
    rule[:must_not_import].each do |forbidden|
      it "lib/textus/#{rule[:from]}/ never references Textus::#{forbidden}::" do
        offenders = layer_files.select { |f| File.read(f).match?(/\bTextus::#{forbidden}::/) }
        expect(offenders).to be_empty,
                             "lib/textus/#{rule[:from]}/ reaches up into Textus::#{forbidden}:: in:\n  " \
                             "#{offenders.map { |f| f.sub(%r{.*/lib/}, "lib/") }.join("\n  ")}"
      end
    end
  end
end
