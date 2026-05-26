require "spec_helper"
require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe "Textus::CLI verb return-value contract" do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human] }
        entries: []
      YAML
      yield root
    end
  end

  def run_cli(argv, cwd:)
    out = StringIO.new
    err = StringIO.new
    code = Textus::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: err, cwd: cwd)
    [code, out.string, err.string]
  end

  it "refresh stale on an empty store returns 0 (was nil → TypeError, #61)" do
    with_store do |root|
      code, _stdout, _stderr = run_cli(%w[refresh stale --prefix=working --as=runner], cwd: root)
      expect(code).to be_an(Integer)
      expect(code).to eq(0)
    end
  end

  it "every registered verb returns an Integer from a no-op invocation" do
    with_store do |root|
      Textus::CLI::VERBS.each_key do |verb|
        code, = run_cli([verb], cwd: root)
        expect(code).to be_an(Integer),
                        "verb `textus #{verb}` returned #{code.inspect} (expected Integer)"
      end
    end
  end
end
