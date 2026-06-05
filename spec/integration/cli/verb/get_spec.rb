require "spec_helper"
require "stringio"

RSpec.describe Textus::CLI::Verb::Get do
  include_context "textus_store_fixture"

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv)
    Textus::CLI.run(["--root=#{root}"] + argv, stdin: StringIO.new(""), stdout: stdout, stderr: stderr, cwd: tmp)
  end

  # A stale intake entry on an on_expire: refresh rule. Since ADR 0089 `get`
  # is a pure read — it never invokes the intake handler.
  before do
    hook_body = <<~RUBY
      Textus.hook do |reg|
        reg.on(:resolve_intake, :test_intake) do |caps:, config:, args:|
          Thread.current[:cli_get_fetch_count] ||= 0
          Thread.current[:cli_get_fetch_count] += 1
          { _meta: { "last_fetched_at" => Time.now.utc.iso8601 }, body: "fresh body" }
        end
      end
    RUBY

    store_from_manifest(
      root,
      zones: %w[feeds],
      files: { "hooks/test_intake.rb" => hook_body },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: feeds, kind: quarantine }
        entries:
          - key: feeds.doc
            kind: intake
            path: feeds/doc.md
            zone: feeds
            intake: { handler: test_intake }
        rules:
          - match: feeds.doc
            upkeep: { "on": stale, ttl: 1s, action: refresh }
      YAML
    )
    File.write(File.join(root, "zones", "feeds", "doc.md"), <<~MD)
      ---
      key: feeds.doc
      last_fetched_at: "2020-01-01T00:00:00Z"
      ---
      old body
    MD
  end

  it "is a pure read: a stale key returns the on-disk stale envelope, never ingesting" do
    Thread.current[:cli_get_fetch_count] = 0
    rc = run(["get", "feeds.doc", "--as=automation"])
    expect(rc).to eq(0), "stderr: #{stderr.string}"
    payload = JSON.parse(stdout.string)
    expect(payload["stale"]).to be(true)
    expect(Thread.current[:cli_get_fetch_count]).to eq(0)
  end
end
