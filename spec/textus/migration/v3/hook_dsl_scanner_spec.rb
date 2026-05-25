require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Migration::V3::HookDSLScanner do
  let(:tmpdir) { Dir.mktmpdir }
  let(:hooks_dir) { File.join(tmpdir, ".textus/hooks") }

  before { FileUtils.mkdir_p(hooks_dir) }
  after  { FileUtils.rm_rf(tmpdir) }

  def write_hook(name, content)
    path = File.join(hooks_dir, name)
    File.write(path, content)
    path
  end

  it "returns an empty array when the hooks directory is empty" do
    expect(described_class.scan(root: tmpdir)).to eq([])
  end

  it "returns an empty array for hooks with no legacy patterns" do
    write_hook("modern.rb", "Textus.on(:resolve_intake) { |e| e }\n")
    expect(described_class.scan(root: tmpdir)).to eq([])
  end

  it "detects Textus.intake( and emits resolve_intake hint" do
    write_hook("legacy.rb", "Textus.intake(:foo) { |e| e }\n")
    findings = described_class.scan(root: tmpdir)
    expect(findings.length).to eq(1)
    expect(findings.first[:hint]).to include("resolve_intake")
    expect(findings.first[:line]).to eq(1)
    expect(findings.first[:original]).to eq("Textus.intake(:foo) { |e| e }")
  end

  it "detects Textus.reduce( and emits transform_rows hint" do
    write_hook("legacy.rb", "Textus.reduce(:bar) { |rows| rows }\n")
    findings = described_class.scan(root: tmpdir)
    expect(findings.length).to eq(1)
    expect(findings.first[:hint]).to include("transform_rows")
  end

  it "detects Textus.hook( and emits Textus.on hint" do
    write_hook("legacy.rb", "Textus.hook(:some_event) { }\n")
    findings = described_class.scan(root: tmpdir)
    expect(findings.length).to eq(1)
    expect(findings.first[:hint]).to include("Textus.on(")
  end

  it "detects Textus.on(:intake) with legacy event symbol" do
    write_hook("legacy.rb", "Textus.on(:intake) { |e| e }\n")
    findings = described_class.scan(root: tmpdir)
    expect(findings.length).to eq(1)
    expect(findings.first[:hint]).to include("resolve_intake")
  end

  it "detects Textus.on(:built) legacy event symbol" do
    write_hook("legacy.rb", "Textus.on(:built) { }\n")
    findings = described_class.scan(root: tmpdir)
    expect(findings.length).to eq(1)
    expect(findings.first[:hint]).to include("build_completed")
  end

  it "detects Textus.on(:refresh_began) and emits refresh_started hint" do
    write_hook("legacy.rb", "Textus.on(:refresh_began) { }\n")
    findings = described_class.scan(root: tmpdir)
    expect(findings.length).to eq(1)
    expect(findings.first[:hint]).to include("refresh_started")
  end

  it "detects Textus.on(:refresh_detached) and emits refresh_backgrounded hint" do
    write_hook("legacy.rb", "Textus.on(:refresh_detached) { }\n")
    findings = described_class.scan(root: tmpdir)
    expect(findings.length).to eq(1)
    expect(findings.first[:hint]).to include("refresh_backgrounded")
  end

  it "reports multiple findings in one file (line numbers are correct)" do
    write_hook("multi.rb", <<~RB)
      Textus.intake(:foo) { |e| e }
      # a comment
      Textus.reduce(:bar) { |rows| rows }
      Textus.check(:baz) { |e| e }
    RB
    findings = described_class.scan(root: tmpdir)
    expect(findings.length).to eq(3)
    expect(findings.map { |f| f[:line] }).to contain_exactly(1, 3, 4)
  end

  it "reports findings across multiple hook files" do
    write_hook("hook_a.rb", "Textus.intake(:x) { }\n")
    write_hook("hook_b.rb", "Textus.put(:y) { }\n")
    findings = described_class.scan(root: tmpdir)
    expect(findings.length).to eq(2)
    paths = findings.map { |f| File.basename(f[:path]) }
    expect(paths).to contain_exactly("hook_a.rb", "hook_b.rb")
  end

  it "includes the :path key pointing to the correct file" do
    path = write_hook("named.rb", "Textus.deleted(:doc) { }\n")
    findings = described_class.scan(root: tmpdir)
    expect(findings.first[:path]).to eq(path)
  end

  it "ignores non-ruby files in the hooks directory" do
    write_hook("readme.md", "Textus.intake(:foo) call\n")
    expect(described_class.scan(root: tmpdir)).to eq([])
  end
end
