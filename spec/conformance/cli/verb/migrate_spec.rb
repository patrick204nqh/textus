require "spec_helper"
require "stringio"

# Generated migrate verb (ADR 0068): reads the plan from a positional path via
# source: :file, and applies by default on the CLI (cli_default: false) while
# agents plan by default — so the boolean flag is --dry-run, not --no-dry-run.
RSpec.describe "textus migrate (generated via source: :file + cli_default)" do
  include_context "textus_store_fixture"

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:plan_path) { File.join(tmp, "plan.yaml") }

  def run(argv)
    Textus::CLI.run(argv, stdin: StringIO.new, stdout: stdout, stderr: stderr, cwd: tmp)
  end

  before do
    %w[zones/working/old zones/working/new].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.old, path: working/old, zone: working, owner: human:self, kind: nested, nested: true }
        - { key: working.new, path: working/new, zone: working, owner: human:self, kind: nested, nested: true }
    YAML
    File.write(File.join(root, "zones/working/old/a.md"), "---\n_meta: {name: a, uid: aaaaaaaaaaaaaaaa}\n---\nA\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
    File.write(plan_path, <<~YAML)
      version: 1
      operations:
        - { op: key_mv_prefix, from_prefix: working.old, to_prefix: working.new }
    YAML
  end

  it "reads the plan file and APPLIES by default (cli_default: false)" do
    rc = run(["--root=#{root}", "migrate", plan_path, "--as=human"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    expect(File.exist?(File.join(root, "zones/working/new/a.md"))).to be(true)
  end

  it "plans only when --dry-run is passed (does not touch files)" do
    rc = run(["--root=#{root}", "migrate", plan_path, "--as=human", "--dry-run"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    expect(File.exist?(File.join(root, "zones/working/old/a.md"))).to be(true)
    expect(File.exist?(File.join(root, "zones/working/new/a.md"))).to be(false)
  end
end
