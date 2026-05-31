require "spec_helper"
require "stringio"

RSpec.describe "textus retain" do
  include_context "textus_store_fixture"

  let(:stdin)  { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv)
    Textus::CLI.run(argv, stdin: stdin, stdout: stdout, stderr: stderr, cwd: tmp)
  end

  it "registers the retention verbs" do
    expect(Textus::Dispatcher::VERBS).to include(:retention_sweep, :retainable)
    expect(Textus::RoleScope.instance_methods).to include(:retention_sweep, :retainable)
  end

  describe "end-to-end: expires an aged leaf" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/review"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: review, kind: canon }
        entries:
          - { key: review.oncall, path: review/oncall.md, zone: review, kind: leaf }

        rules:
          - match: "review.*"
            retention: { expire_after: 30d }
      YAML

      leaf_path = File.join(root, "zones/review/oncall.md")
      File.write(leaf_path, "# oncall notes\n")
      forty_days_ago = Time.now - (40 * 86_400)
      File.utime(forty_days_ago, forty_days_ago, leaf_path)
    end

    it "reports the expired leaf and removes the file" do
      leaf_path = File.join(root, "zones/review/oncall.md")
      expect(File.exist?(leaf_path)).to be(true)

      rc = run(%w[retain --as=human])
      expect(rc).to eq(0)

      payload = JSON.parse(stdout.string)
      expect(payload["ok"]).to be(true)
      expect(payload["expired"]).to include("review.oncall")
      expect(File.exist?(leaf_path)).to be(false)
    end
  end
end
