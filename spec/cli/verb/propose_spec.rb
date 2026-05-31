require "spec_helper"
require "stringio"

RSpec.describe Textus::CLI::Verb::Propose do
  include_context "textus_store_fixture"

  let(:stdin) { StringIO.new }
  let(:manifest_yaml) do
    <<~YAML
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: proposals, kind: queue }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, zone: knowledge, schema: null, owner: human:self, nested: true, kind: nested }
        - { key: proposals, path: proposals, zone: proposals, schema: null, owner: agent, nested: true, kind: nested }
    YAML
  end
  let(:store) { Textus::Store.new(root) }
  let(:propose_zone) do
    store.manifest.policy.propose_zone_for(store.manifest.policy.proposer_role)
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
    Textus::CLI.run(
      argv,
      stdin: StringIO.new(stdin_body),
      stdout: stdout,
      stderr: stderr,
      cwd: tmp,
    )
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/notes"))
    FileUtils.mkdir_p(File.join(root, "zones/proposals"))
    File.write(File.join(root, "manifest.yaml"), manifest_yaml)
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  it "lands the entry under the propose_zone (key becomes <propose_zone>.notes.oncall) and exits 0" do
    rc = run(
      ["--root=#{root}", "propose", "notes.oncall", "--as=agent", "--stdin"],
      stdin_body: payload,
    )
    expect(rc).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"

    result = JSON.parse(stdout.string)
    expected_key = "#{propose_zone}.notes.oncall"
    expect(result["key"]).to eq(expected_key)
    expect(File.exist?(File.join(root, "zones/#{propose_zone}/notes/oncall.md"))).to be(true)
  end

  it "raises UsageError mentioning stdin when --stdin is omitted" do
    rc = run(["--root=#{root}", "propose", "notes.x", "--as=agent"])
    expect(rc).not_to eq(0)
    output = JSON.parse(stdout.string)
    expect(output["message"]).to match(/stdin/)
  end

  it "raises UsageError mentioning propose_zone when the acting role cannot write the queue" do
    # `automation` has only `fetch`/`build` caps — propose_zone_for("automation") => nil
    rc = run(
      ["--root=#{root}", "propose", "notes.x", "--as=automation", "--stdin"],
      stdin_body: payload,
    )
    expect(rc).not_to eq(0)
    output = JSON.parse(stdout.string)
    expect(output["message"]).to match(/propose_zone/)
  end
end
