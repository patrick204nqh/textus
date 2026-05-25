require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Migration::V3 do
  let(:tmp) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmp) }

  before do
    FileUtils.mkdir_p(File.join(tmp, ".textus/zones/inbox"))
    File.write(File.join(tmp, ".textus/manifest.yaml"), <<~Y)
      version: textus/2
      zones:
        - { name: inbox, writable_by: [script], readable_by: all }
      entries:
        - key: inbox.cal
          zone: inbox
          path: cal.md
          format: markdown
          owner: script:cron
      policies:
        - match: "inbox.cal.*"
          handler_allowlist: [ical-events]
    Y
    File.write(File.join(tmp, ".textus/zones/inbox/cal.md"), "---\nowner: script:cron\n---\nx\n")
    File.write(File.join(tmp, ".textus/audit.log"), "")
  end

  it "migrates manifest, zones, frontmatter, and audit log in one pass" do
    Textus::Migration::V3.run(root: tmp)

    manifest = File.read(File.join(tmp, ".textus/manifest.yaml"))
    expect(manifest).to include("version: textus/3")
    expect(manifest).to include("intake")
    expect(manifest).not_to match(/^[[:space:]]*name: inbox/)

    expect(Dir.exist?(File.join(tmp, ".textus/zones/intake"))).to be true
    expect(Dir.exist?(File.join(tmp, ".textus/zones/inbox"))).to be false

    cal = File.read(File.join(tmp, ".textus/zones/intake/cal.md"))
    expect(cal).to include("runner:cron")
    expect(cal).not_to include("script:cron")

    expect(File.read(File.join(tmp, ".textus/audit.log"))).to include("migration-marker")
  end

  it "is idempotent — running twice does not double-mark" do
    Textus::Migration::V3.run(root: tmp)
    expect { Textus::Migration::V3.run(root: tmp) }.not_to raise_error
    markers = File.read(File.join(tmp, ".textus/audit.log"))
                  .each_line.count { |l| l.include?("migration-marker") }
    expect(markers).to eq(1)
  end

  it "reports hook DSL findings" do
    FileUtils.mkdir_p(File.join(tmp, ".textus/hooks"))
    File.write(File.join(tmp, ".textus/hooks/x.rb"), "Textus.intake(:foo) { }\n")
    result = Textus::Migration::V3.run(root: tmp)
    expect(result[:hook_findings].size).to eq(1)
    expect(result[:hook_findings].first[:hint]).to include(":resolve_intake")
  end

  it "honors dry_run: does not modify files but still scans hooks" do
    pre = File.read(File.join(tmp, ".textus/manifest.yaml"))
    result = Textus::Migration::V3.run(root: tmp, dry_run: true)
    expect(File.read(File.join(tmp, ".textus/manifest.yaml"))).to eq(pre)
    expect(Dir.exist?(File.join(tmp, ".textus/zones/inbox"))).to be true
    expect(result[:dry_run]).to be true
  end
end
