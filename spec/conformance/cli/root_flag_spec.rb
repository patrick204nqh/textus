# frozen_string_literal: true

require "open3"

RSpec.describe "textus --root" do
  let(:tmp) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmp) }

  it "uses the --root path for store discovery" do
    custom = File.join(tmp, "store")
    FileUtils.mkdir_p(File.join(custom, "schemas"))
    FileUtils.mkdir_p(File.join(custom, "zones"))
    File.write(File.join(custom, "manifest.yaml"),
               "version: textus/3\nzones:\n  - { name: knowledge, kind: canon }\nentries: []\n")

    exe = File.expand_path("../../../exe/textus", __dir__)
    stdout, _stderr, status = Open3.capture3("ruby", "-I", File.expand_path("../../../lib", __dir__), exe, "--root=#{custom}", "list",
                                             "--output=json")
    expect(status.exitstatus).to eq(0)
    payload = JSON.parse(stdout)
    expect(payload.fetch("entries")).to eq([])
  end

  # F5 (#161): --root is position-agnostic — it works after a verb and after a
  # group subcommand, not only before the verb.
  def store_with_manifest
    custom = File.join(tmp, "store")
    FileUtils.mkdir_p(File.join(custom, "schemas"))
    FileUtils.mkdir_p(File.join(custom, "zones"))
    File.write(File.join(custom, "manifest.yaml"),
               "version: textus/3\nzones:\n  - { name: knowledge, kind: canon }\nentries: []\n")
    custom
  end

  def run_cli(*argv)
    exe = File.expand_path("../../../exe/textus", __dir__)
    Open3.capture3("ruby", "-I", File.expand_path("../../../lib", __dir__), exe, *argv)
  end

  it "accepts --root after the verb (textus list --root=PATH)" do
    custom = store_with_manifest
    stdout, _stderr, status = run_cli("list", "--root=#{custom}", "--output=json")
    expect(status.exitstatus).to eq(0)
    expect(JSON.parse(stdout).fetch("entries")).to eq([])
  end

  it "accepts --root after a group subcommand (textus hook list --root=PATH)" do
    custom = store_with_manifest
    FileUtils.mkdir_p(File.join(custom, "hooks"))
    stdout, _stderr, status = run_cli("hook", "list", "--root=#{custom}", "--output=json")
    expect(status.exitstatus).to eq(0)
    expect(JSON.parse(stdout)).to have_key("hooks")
  end

  it "accepts the space form --root PATH after the verb" do
    custom = store_with_manifest
    stdout, _stderr, status = run_cli("list", "--root", custom, "--output=json")
    expect(status.exitstatus).to eq(0)
    expect(JSON.parse(stdout).fetch("entries")).to eq([])
  end

  it "exits non-zero when --root has no manifest" do
    bogus = File.join(tmp, "no-manifest")
    FileUtils.mkdir_p(bogus)
    exe = File.expand_path("../../../exe/textus", __dir__)
    _stdout, stderr, status = Open3.capture3("ruby", "-I", File.expand_path("../../../lib", __dir__), exe, "--root=#{bogus}", "list",
                                             "--output=json")
    expect(status.exitstatus).not_to eq(0)
    expect(stderr).to match(/no textus store/i)
  end
end
