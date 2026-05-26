require "spec_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"

RSpec.describe "textus build concurrency" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/output"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
        - { name: output, write_policy: [builder] }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: null }
        - key: output.note
          path: output/note.md
          zone: output
          schema: null
          owner: builder:auto
          compute: { kind: projection, select: working.note }
          template: echo.mustache
    YAML

    File.write(File.join(root, "templates/echo.mustache"), "hello {{key}}\n")
    File.write(File.join(root, "zones/working/note.md"),
               "---\nkey: working.note\n---\nbody\n")
  end

  it "second concurrent build exits 75 with build_in_progress code" do
    lock_path = File.join(root, Textus::Infra::BuildLock::LOCK_FILENAME)
    # rubocop:disable Style/FileOpen
    lock_fd = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
    # rubocop:enable Style/FileOpen
    lock_fd.flock(File::LOCK_EX | File::LOCK_NB) or raise "test setup: could not acquire lock"
    lock_fd.write("pid=99999 started=2026-05-26T00:00:00Z host=test\n")
    lock_fd.flush

    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Textus::CLI.run(["--root=#{root}", "build"],
                                stdin: StringIO.new(""), stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(75)
    envelope = JSON.parse(stdout.string.lines.last)
    expect(envelope["ok"]).to be false
    expect(envelope["code"]).to eq("build_in_progress")
    expect(envelope["details"]["holder"]).to match(/pid=99999/)
    expect(stderr.string).to include("build_in_progress")
  ensure
    lock_fd&.close
  end
end
