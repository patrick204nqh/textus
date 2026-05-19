require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"

RSpec.describe "Manifest hooks block" do
  let(:tmp) { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/intake/upstream"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: intake, writable_by: [script] }
      entries:
        - key: intake.releases
          path: intake/upstream/releases.md
          zone: intake
          schema: null
          owner: script:cron
          source: { from: https://example.com/r.rss, parse: rss, ttl: 6h }
          hooks:
            on_stale:
              - { run: scripts/x.sh, as: script }
    YAML
    File.write(File.join(root, "zones/intake/upstream/releases.md"),
               "---\nname: releases\n---\nbody\n")
  end

  after { FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp) }

  it "exposes hooks per entry" do
    manifest = Textus::Manifest.load(root)
    e = manifest.entries.find { |x| x.key == "intake.releases" }
    expect(e.hooks["on_stale"].first["run"]).to eq("scripts/x.sh")
  end

  it "lists hooks filtered by event via CLI" do
    out = StringIO.new
    rc = Textus::CLI.run(
      ["hooks", "list", "--event=on_stale", "--format=json"],
      stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
    )
    expect(rc).to eq(0)
    env = JSON.parse(out.string.lines.last)
    expect(env["hooks"].first["event"]).to eq("on_stale")
  end
end
