require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"
require "yaml"

RSpec.describe "textus migrate group" do
  let(:tmp)    { Dir.mktmpdir }
  let(:root)   { File.join(tmp, ".textus") }
  let(:stdin)  { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv)
    Textus::CLI.run(argv, stdin: stdin, stdout: stdout, stderr: stderr, cwd: tmp)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/canon"))
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "zones/pending"))
    FileUtils.mkdir_p(File.join(root, "zones/derived"))
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: working, writable_by: [human, ai, script] }
        - { name: intake,  writable_by: [script] }
        - { name: pending, writable_by: [ai, human] }
        - { name: derived, writable_by: [build] }
      entries:
        - key: inbox.news.hn
          zone: intake
          path: intake/news/hn.md
          intake: { handler: http_get, ttl: 6h, on_stale: refresh }
      policies:
        - match: "intake.news.*"
          refresh: { ttl: 6h, on_stale: refresh }
    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  describe "textus migrate zones" do
    it "rewrites zones, entries, policy matches and emits an envelope" do
      rc = run(%w[migrate zones])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["verb"]).to eq("migrate.zones")
      expect(payload["dry_run"]).to be(false)
      expect(payload["changes"]).not_to be_empty

      yaml = YAML.load_file(File.join(root, "manifest.yaml"))
      names = yaml["zones"].map { |z| z["name"] }
      expect(names).to contain_exactly("identity", "working", "inbox", "review", "output")
      expect(yaml["policies"][0]["match"]).to eq("inbox.news.*")
      expect(Dir.exist?(File.join(root, "zones/inbox"))).to be(true)
    end

    it "honours --dry-run" do
      rc = run(%w[migrate zones --dry-run])
      expect(rc).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["dry_run"]).to be(true)
      expect(Dir.exist?(File.join(root, "zones/canon"))).to be(true)
    end
  end

  describe "textus migrate (no subcommand)" do
    it "lists valid subcommands" do
      run(["migrate"])
      err = JSON.parse(stdout.string)
      expect(err["code"]).to eq("usage")
      expect(stderr.string).to match(/migrate requires a subcommand:.*zones.*policies/i)
    end
  end
end
