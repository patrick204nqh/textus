require "spec_helper"

# `blame` is a generated verb (ADR 0065): the CLI command is projected from the
# contract via an arity-2 `cli_response`, no longer a hand-authored class. These
# behavioral specs still exercise the projected command end-to-end.
RSpec.describe "blame CLI (generated, ADR 0065)" do
  include_context "textus_store_fixture"
  include_context "cli invocation"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.doc, path: data/knowledge/doc.md, lane: knowledge, kind: leaf}

    YAML
    File.write(File.join(root, "data/knowledge/doc.md"), "---\nname: doc\n---\nbody\n")
    FileUtils.mkdir_p(audit_dir_path(root))
    File.open(audit_log_path(root), "w") do |f|
      f.puts JSON.generate({ "ts" => "2026-05-01T00:00:00Z", "role" => "human",
                             "verb" => "put", "key" => "knowledge.doc" })
    end
  end

  it "emits a JSON envelope with verb=blame, key, and rows (git nil without a repo)" do
    rc = run(["blame", "knowledge.doc"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload["verb"]).to eq("blame")
    expect(payload["key"]).to eq("knowledge.doc")
    expect(payload["rows"].length).to eq(1)
    expect(payload["rows"].first["git"]).to be_nil
  end

  it "raises UsageError when no key is supplied" do
    rc = run(["blame"])
    err = JSON.parse(stdout.string)
    expect(err["code"]).to eq("usage")
    expect(rc).not_to eq(0)
  end
end
