require "spec_helper"
require "tmpdir"
require "stringio"
require "json"
require "fileutils"

RSpec.describe "textus action verb" do
  def custom_manifest_with_demo!(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, write_policy: [human] }
        - { name: working,  write_policy: [human, agent, runner] }
        - { name: intake,   write_policy: [runner] }
        - { name: review,   write_policy: [agent, human] }
        - { name: output,   write_policy: [builder] }
      entries:
        - { key: working.demo, path: working/demo.md, zone: working, kind: leaf}

    YAML
  end

  it "invokes the named action with parsed args and returns ok" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, ".textus")
      Textus::Init.run(root)
      custom_manifest_with_demo!(root)
      File.write(File.join(root, "hooks/sync.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :sync_demo) do |caps:, config:, args:|
            _ = caps
            { _meta: { "name" => "demo", "who" => args["who"] || "anon" }, body: "ok" }
          end
        end
      RUBY

      stdout = StringIO.new
      stderr = StringIO.new
      rc = Textus::CLI.run(
        ["--root=#{root}", "hook", "run", "sync_demo", "--who=patrick", "--as=human"],
        stdin: StringIO.new(""), stdout: stdout, stderr: stderr, cwd: dir,
      )
      expect(rc).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"

      payload = JSON.parse(stdout.string.lines.last)
      expect(payload["action"]).to eq("sync_demo")
      expect(payload["ok"]).to be true
    end
  end

  it "raises usage error when action name is missing" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, ".textus")
      Textus::Init.run(root)
      out = StringIO.new
      rc = Textus::CLI.run(
        ["--root=#{root}", "hook", "run"],
        stdin: StringIO.new(""), stdout: out, stderr: StringIO.new, cwd: dir,
      )
      expect(rc).not_to eq(0)
      expect(JSON.parse(out.string.lines.last)["message"]).to match(/requires a name/)
    end
  end

  it "captures a timeout from a slow action" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, ".textus")
      Textus::Init.run(root)
      File.write(File.join(root, "hooks/slow.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :slow) { |caps:, config:, args:| sleep 5 }
        end
      RUBY
      allow(Timeout).to receive(:timeout).and_call_original
      allow(Timeout).to receive(:timeout)
        .with(Textus::Application::Write::RefreshWorker::FETCH_TIMEOUT_SECONDS)
        .and_raise(Timeout::Error)
      out = StringIO.new
      rc = Textus::CLI.run(
        ["--root=#{root}", "hook", "run", "slow", "--as=runner"],
        stdin: StringIO.new(""), stdout: out, stderr: StringIO.new, cwd: dir,
      )
      expect(rc).not_to eq(0)
      expect(JSON.parse(out.string.lines.last)["message"]).to match(/timeout/)
    end
  end
end
