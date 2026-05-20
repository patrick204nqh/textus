require "spec_helper"
require "tmpdir"
require "stringio"
require "json"
require "fileutils"

RSpec.describe "textus action verb" do
  def custom_manifest_with_demo!(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: working, writable_by: [human, ai, script] }
        - { name: intake,  writable_by: [script] }
        - { name: pending, writable_by: [ai, human] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: working.demo, path: working/demo.md, zone: working }
    YAML
  end

  it "invokes the named action with parsed args and lets it write via store.put" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, ".textus")
      Textus::Init.run(root)
      custom_manifest_with_demo!(root)
      File.write(File.join(root, "extensions/sync.rb"), <<~RUBY)
        Textus.action(:sync_demo) do |config:, store:, args:|
          store.put("working.demo", frontmatter: { "name" => "demo", "who" => args["who"] || "anon" }, body: "ok")
        end
      RUBY

      stdout = StringIO.new
      stderr = StringIO.new
      rc = Textus::CLI.run(
        ["--root=#{root}", "action", "sync_demo", "--who=patrick", "--as=human"],
        stdin: StringIO.new(""), stdout: stdout, stderr: stderr, cwd: dir,
      )
      expect(rc).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"

      payload = JSON.parse(stdout.string.lines.last)
      expect(payload["action"]).to eq("sync_demo")
      expect(payload["ok"]).to be true

      store = Textus::Store.new(root)
      env = store.get("working.demo")
      expect(env["frontmatter"]["who"]).to eq("patrick")
    end
  end

  it "raises usage error when action name is missing" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, ".textus")
      Textus::Init.run(root)
      out = StringIO.new
      rc = Textus::CLI.run(
        ["--root=#{root}", "action"],
        stdin: StringIO.new(""), stdout: out, stderr: StringIO.new, cwd: dir,
      )
      expect(rc).not_to eq(0)
      expect(JSON.parse(out.string.lines.last)["message"]).to match(/action requires a name/)
    end
  end

  it "captures a timeout from a slow action" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, ".textus")
      Textus::Init.run(root)
      File.write(File.join(root, "extensions/slow.rb"), <<~RUBY)
        Textus.action(:slow) { |config:, store:, args:| sleep 5 }
      RUBY
      allow(Timeout).to receive(:timeout).and_call_original
      allow(Timeout).to receive(:timeout)
        .with(Textus::Refresh::ACTION_TIMEOUT_SECONDS)
        .and_raise(Timeout::Error)
      out = StringIO.new
      rc = Textus::CLI.run(
        ["--root=#{root}", "action", "slow", "--as=script"],
        stdin: StringIO.new(""), stdout: out, stderr: StringIO.new, cwd: dir,
      )
      expect(rc).not_to eq(0)
      expect(JSON.parse(out.string.lines.last)["message"]).to match(/timeout/)
    end
  end
end
