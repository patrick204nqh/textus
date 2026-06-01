require "spec_helper"

# Regression test for Staleness: it must detect generator-kind zones via the
# kind: derived signal (the zone-kind that requires the `build` capability),
# not via the literal zone name "derived". Prior to signal-based detection,
# post-0.9.2 default `artifacts` zones were skipped entirely.
RSpec.describe "Textus::Domain::Staleness signal-based generator-zone detection" do
  include_context "textus_store_fixture"

  def build_output_zone_fixture!
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts,  kind: derived }
      entries:
        - key: knowledge.src
          kind: leaf
          path: knowledge/src.md
          zone: knowledge
        - key: artifacts.catalog
          kind: derived
          path: artifacts/catalog.md
          zone: artifacts
          compute:
            kind: external
            command: "rake catalog"
            sources: [knowledge.src]
    YAML
    File.write(File.join(root, "zones/knowledge/src.md"), "---\nname: src\n---\nbody\n")
    File.write(File.join(root, "zones/artifacts/catalog.md"), <<~MD)
      ---
      generated:
        by: "rake catalog"
        at: "2020-01-01T00:00:00Z"
        from:
          - knowledge.src
      ---
      catalog
    MD
    File.utime(Time.now, Time.now, File.join(root, "zones/knowledge/src.md"))
  end

  it "flags a generator entry in a zone literally named 'artifacts' (post-0.9.2 default)" do
    build_output_zone_fixture!
    store = Textus::Store.new(root)
    rows = store.as(Textus::Role::DEFAULT).stale
    expect(rows.length).to eq(1)
    expect(rows.first["key"]).to eq("artifacts.catalog")
    expect(rows.first["reason"]).to match(/knowledge\.src/)
  end

  # Closes Known-risk: the file? helper skips directories under a glob so that
  # subdirectories inside a source tree do not crash mtime resolution. Only the
  # regular file's mtime drives the staleness result.
  def build_dir_source_fixture!
    src_dir = File.join(tmp, "src")
    FileUtils.mkdir_p(File.join(src_dir, "subdir"))
    File.write(File.join(src_dir, "data.txt"), "content")
    future = Time.now + 3600
    [File.join(src_dir, "subdir"), File.join(src_dir, "data.txt")].each do |f|
      File.utime(future, future, f)
    end
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: artifacts, kind: derived }
      entries:
        - key: artifacts.report
          kind: derived
          path: artifacts/report.md
          zone: artifacts
          compute:
            kind: external
            command: "make report"
            sources: ["#{src_dir}"]
    YAML
    File.write(File.join(root, "zones/artifacts/report.md"), <<~MD)
      ---
      generated:
        by: "make report"
        at: "2020-01-01T00:00:00Z"
        from: []
      ---
      report
    MD
  end

  it "filesystem-source directory: skips subdirs under glob, flags staleness from a regular file" do
    build_dir_source_fixture!
    store = Textus::Store.new(root)
    rows = store.as(Textus::Role::DEFAULT).stale

    expect(rows.length).to eq(1)
    expect(rows.first["key"]).to eq("artifacts.report")
    expect(rows.first["reason"]).to match(/modified after generated\.at/)
  end

  it "negative-signal: a zone literally named 'derived' but with kind: canon is NOT generator-kind" do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: derived, kind: canon }
      entries:
        - key: knowledge.src
          kind: leaf
          path: knowledge/src.md
          zone: knowledge
        - key: derived.note
          kind: derived
          path: derived/note.md
          zone: derived
          compute:
            kind: external
            command: "echo"
            sources: [knowledge.src]
    YAML

    File.write(File.join(root, "zones/knowledge/src.md"), "---\nname: src\n---\nbody\n")
    # No file at derived/note.md → if treated as generator zone, would be flagged
    # with "derived entry has never been generated". Because the zone declares
    # kind: canon (not derived), it must NOT be inspected by Staleness's
    # generator pass.

    store = Textus::Store.new(root)
    rows = store.as(Textus::Role::DEFAULT).stale
    expect(rows).to eq([])
  end
end
