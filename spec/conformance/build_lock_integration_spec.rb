require "spec_helper"
require "stringio"

RSpec.describe "textus drain concurrency (build lock)" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts"))
    FileUtils.mkdir_p(File.join(root, "templates"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, kind: leaf}

        - key: artifacts.note
          kind: produced
          path: artifacts/note.json
          lane: artifacts
          owner: automation:auto
          source: { from: external, command: "make", sources: [] }
          publish:
            - { to: NOTE.md, template: echo.erb }
    YAML

    File.write(File.join(root, "templates/echo.erb"), "hello <%= key %>\n")
    File.write(File.join(root, "data/knowledge/note.md"),
               "---\nkey: knowledge.note\n---\nbody\n")
  end

  # Queue-model contract (replaces the old "second pass exits 75"): drain runs
  # produce per-job through Produce::Engine.converge, which treats a held build
  # lock as a SOFT MISS (an in-flight build is already producing fresh output;
  # ADR 0087 §5) rather than crashing. A concurrent drain degrades gracefully —
  # it exits 0, never hard-fails with build_in_progress.
  it "soft-misses gracefully (exit 0) when the build lock is already held" do
    lock_path = Textus::StoreGeometry.new(root).lock_path("build")
    FileUtils.mkdir_p(File.dirname(lock_path))
    # rubocop:disable Style/FileOpen
    lock_fd = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
    # rubocop:enable Style/FileOpen
    lock_fd.flock(File::LOCK_EX | File::LOCK_NB) or raise "test setup: could not acquire lock"
    lock_fd.write("pid=99999 started=2026-05-26T00:00:00Z host=test\n")
    lock_fd.flush

    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Textus::Surfaces::CLI.run(["--root=#{root}", "drain"],
                                          stdin: StringIO.new(""), stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(0)
    envelope = JSON.parse(stdout.string.lines.last)
    expect(envelope["ok"]).to be true
  ensure
    lock_fd&.close
  end
end
