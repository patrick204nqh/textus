# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "fileutils"

RSpec.describe "textus --root" do
  let(:tmp) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmp) }

  it "uses the --root path for store discovery" do
    custom = File.join(tmp, "store")
    FileUtils.mkdir_p(File.join(custom, "schemas"))
    FileUtils.mkdir_p(File.join(custom, "zones"))
    File.write(File.join(custom, "manifest.yaml"), "version: textus/3\nzones:\n  - { name: working, write_policy: [human] }\nentries: []\n")

    exe = File.expand_path("../../exe/textus", __dir__)
    stdout, _stderr, status = Open3.capture3("ruby", "-I", File.expand_path("../../lib", __dir__), exe, "--root=#{custom}", "list",
                                             "--format=json")
    expect(status.exitstatus).to eq(0)
    payload = JSON.parse(stdout)
    expect(payload.fetch("entries")).to eq([])
  end

  it "exits non-zero when --root has no manifest" do
    bogus = File.join(tmp, "no-manifest")
    FileUtils.mkdir_p(bogus)
    exe = File.expand_path("../../exe/textus", __dir__)
    _stdout, stderr, status = Open3.capture3("ruby", "-I", File.expand_path("../../lib", __dir__), exe, "--root=#{bogus}", "list",
                                             "--format=json")
    expect(status.exitstatus).not_to eq(0)
    expect(stderr).to match(/no textus store/i)
  end
end
