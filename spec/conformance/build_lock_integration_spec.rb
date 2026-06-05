require "spec_helper"
require "stringio"

RSpec.describe "textus reconcile concurrency (build lock)" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: derived }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, zone: knowledge, kind: leaf}

        - key: artifacts.note
          kind: derived
          path: artifacts/note.md
          zone: artifacts
          owner: automation:auto
          compute: { kind: projection, select: knowledge.note }
          template: echo.mustache
    YAML

    File.write(File.join(root, "templates/echo.mustache"), "hello {{key}}\n")
    File.write(File.join(root, "zones/knowledge/note.md"),
               "---\nkey: knowledge.note\n---\nbody\n")
  end

  it "second concurrent reconcile exits 75 with build_in_progress code" do
    lock_path = Textus::Layout.build_lock(root)
    FileUtils.mkdir_p(File.dirname(lock_path))
    # rubocop:disable Style/FileOpen
    lock_fd = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
    # rubocop:enable Style/FileOpen
    lock_fd.flock(File::LOCK_EX | File::LOCK_NB) or raise "test setup: could not acquire lock"
    lock_fd.write("pid=99999 started=2026-05-26T00:00:00Z host=test\n")
    lock_fd.flush

    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Textus::CLI.run(["--root=#{root}", "reconcile"],
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
