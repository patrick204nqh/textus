require "spec_helper"

# Generated zone mv verb (ADR 0068): from/to are positional, and dry_run carries
# cli_default: false so the CLI APPLIES by default while agents (MCP/Ruby) PLAN
# by default — the surface divergence ADR 0060 once hid in a hand class, now
# legible in the contract.
RSpec.describe "textus zone mv (generated, ADR 0068)" do
  include_context "textus_store_fixture"
  include_context "cli invocation"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/scratch"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: scratch, kind: canon }
      entries:
        - { key: scratch.note, path: scratch/note.md, zone: scratch, owner: human:self, kind: leaf }
    YAML
    File.write(File.join(root, "zones/scratch/note.md"), "---\n_meta: {name: note, uid: nnnnnnnnnnnnnnnn}\n---\nN\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  it "APPLIES the rename by default (cli_default: false) — positional from/to" do
    rc = run(["--root=#{root}", "zone", "mv", "scratch", "sandbox", "--as=human"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    expect(Dir.exist?(File.join(root, "zones/sandbox"))).to be(true)
    expect(Dir.exist?(File.join(root, "zones/scratch"))).to be(false)
  end

  it "plans only when --dry-run is passed (files untouched)" do
    rc = run(["--root=#{root}", "zone", "mv", "scratch", "sandbox", "--as=human", "--dry-run"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    expect(Dir.exist?(File.join(root, "zones/scratch"))).to be(true)
    expect(Dir.exist?(File.join(root, "zones/sandbox"))).to be(false)
  end
end
