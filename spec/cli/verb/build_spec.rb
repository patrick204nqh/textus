require "spec_helper"
require "stringio"

RSpec.describe Textus::CLI::Verb::Build do
  include_context "textus_store_fixture"

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv)
    Textus::CLI.run(["--root=#{root}"] + argv, stdin: StringIO.new(""), stdout: stdout, stderr: stderr, cwd: tmp)
  end

  context "when a non-default legal role holds build" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/output"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: agent, can: [propose, build] }
        zones:
          - { name: output, kind: derived }
        entries: []
      YAML
    end

    it "resolves the build-holder by capability and exits 0" do
      rc = run(["build"])
      expect(rc).to eq(0), "stderr: #{stderr.string}"
      expect(stderr.string).to eq("")
    end
  end

  context "when no role holds build" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: human, can: [author, propose] }
        zones:
          - { name: knowledge, kind: canon }
        entries: []
      YAML
    end

    it "fails loudly with a clear message instead of acting as a phantom role" do
      rc = run(["build"])
      expect(rc).to eq(2)
      expect(stderr.string).to include("no role holds the 'build' capability")
    end
  end
end
