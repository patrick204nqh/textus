require "spec_helper"

RSpec.describe "textus tend" do
  include_context "textus_store_fixture"
  include_context "cli invocation"

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
          lifecycle: { ttl: 30d, on_expire: drop }
    YAML

    leaf = File.join(root, "zones/review/oncall.md")
    File.write(leaf, "# oncall notes\n")
    aged = Time.now - (40 * 86_400)
    File.utime(aged, aged, leaf)
  end

  it "runs the sweep and drops the aged leaf" do
    leaf = File.join(root, "zones/review/oncall.md")

    rc = run(%w[tend --as=human])
    expect(rc).to eq(0)

    payload = JSON.parse(stdout.string)
    expect(payload["ok"]).to be(true)
    expect(payload["dropped"]).to include("review.oncall")
    expect(File.exist?(leaf)).to be(false)
  end

  it "with --dry-run reports the sweep without deleting" do
    leaf = File.join(root, "zones/review/oncall.md")

    rc = run(%w[tend --dry-run --as=human])
    expect(rc).to eq(0)

    payload = JSON.parse(stdout.string)
    expect(payload["dry_run"]).to be(true)
    expect(payload["would_drop"]).to include("review.oncall")
    expect(File.exist?(leaf)).to be(true)
  end
end
