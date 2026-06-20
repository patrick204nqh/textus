require "spec_helper"
require "tmpdir"

RSpec.describe Textus::CursorStore do
  subject(:cursor) { described_class.new(root: root, role: :agent) }

  let(:tmp) { Dir.mktmpdir }
  let(:root) { tmp }

  after { FileUtils.rm_rf(tmp) }

  it "reads 0 when no cursor has been written" do
    expect(cursor.read).to eq(0)
  end

  it "round-trips a written cursor" do
    cursor.write(1842)
    expect(described_class.new(root: root, role: :agent).read).to eq(1842)
  end

  it "keeps cursors separate per role" do
    cursor.write(10)
    expect(described_class.new(root: root, role: :human).read).to eq(0)
  end

  it "writes the cursor under .state/cursors" do
    described_class.new(root: root, role: "agent").write(42)
    expect(File.read(Textus::StoreGeometry.new(root).cursor_path("agent"))).to eq("42")
  end
end
