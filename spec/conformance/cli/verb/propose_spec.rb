require "spec_helper"
require "stringio"

RSpec.describe "textus propose (generated via cli_stdin :json, ADR 0068)" do
  include_context "textus_store_fixture"

  let(:stdin) { StringIO.new }
  let(:manifest_yaml) do
    <<~YAML
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
        - { name: proposals, kind: queue }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, lane: knowledge, owner: human:self, kind: nested }
        - { key: proposals, path: proposals, lane: proposals, owner: agent, kind: nested }
    YAML
  end
  let(:store) { Textus::Store.new(root) }
  let(:propose_lane) do
    store.manifest.policy.propose_lane_for(store.manifest.policy.proposer_role)
  end
  let(:payload) do
    JSON.generate({
                    "_meta" => {
                      "name" => "oncall",
                      "proposal" => { "target_key" => "knowledge.notes.oncall", "action" => "put" },
                    },
                    "body" => "Patrick on call.\n",
                  })
  end
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv, stdin_body: "")
    Textus::Surfaces::CLI.run(
      argv,
      stdin: StringIO.new(stdin_body),
      stdout: stdout,
      stderr: stderr,
      cwd: tmp,
    )
  end

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge/notes"))
    FileUtils.mkdir_p(File.join(root, "data/proposals"))
    File.write(File.join(root, "manifest.yaml"), manifest_yaml)
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  it "lands the entry under the propose_lane (key becomes <propose_lane>.notes.oncall) and exits 0" do
    rc = run(
      ["--root=#{root}", "propose", "notes.oncall", "--as=agent", "--stdin"],
      stdin_body: payload,
    )
    expect(rc).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"

    result = JSON.parse(stdout.string)
    expected_key = "#{propose_lane}.notes.oncall"
    expect(result["key"]).to eq(expected_key)
    expect(File.exist?(File.join(root, "data/#{propose_lane}/notes/oncall.md"))).to be(true)
  end

  it "emits the full wire envelope (uid, etag, key) from a single self-shaping view" do
    rc = run(
      ["--root=#{root}", "propose", "notes.oncall", "--as=agent", "--stdin"],
      stdin_body: payload,
    )
    expect(rc).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"
    parsed = JSON.parse(stdout.string)
    expect(parsed).to include("uid", "etag", "key")
  end

  it "accepts a propose with no piped envelope (ADR 0069: _meta is optional)" do
    # ADR 0069: `_meta` is no longer a pre-dispatch required arg — its real
    # requiredness lives in schema validation downstream. With nothing piped the
    # proposal lands with empty meta rather than erroring on a missing _meta.
    rc = run(["--root=#{root}", "propose", "notes.x", "--as=agent"])
    expect(rc).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"
    result = JSON.parse(stdout.string)
    expect(result["key"]).to eq("#{propose_lane}.notes.x")
  end

  it "raises UsageError mentioning propose_lane when the acting role cannot write the queue" do
    # `automation` has only `fetch`/`build` caps — propose_lane_for("automation") => nil
    rc = run(
      ["--root=#{root}", "propose", "notes.x", "--as=automation", "--stdin"],
      stdin_body: payload,
    )
    expect(rc).not_to eq(0)
    output = JSON.parse(stdout.string)
    expect(output["message"]).to match(/propose_lane/)
  end
end
