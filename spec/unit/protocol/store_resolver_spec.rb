RSpec.describe Textus::Protocol::StoreResolver do
  around { |ex| Dir.mktmpdir { |dir| @dir = dir; ex.run } }

  def with_textus(dir = @dir)
    FileUtils.mkdir_p(File.join(dir, ".textus"))
    dir
  end

  it "uses TEXTUS_ROOT env override" do
    root = with_textus
    result = described_class.resolve(env: { "TEXTUS_ROOT" => root }, cwd: "/tmp")
    expect(result).to eq(root)
  end

  it "walks up from cwd to find .textus" do
    nested = File.join(@dir, "a", "b", "c")
    FileUtils.mkdir_p(nested)
    with_textus(@dir)
    result = described_class.resolve(env: {}, cwd: nested)
    expect(result).to eq(@dir)
  end

  it "raises IoError when no store found" do
    expect { described_class.resolve(env: {}, cwd: "/tmp") }
      .to raise_error(Textus::IoError, /no \.textus store found/)
  end

  it "prefers env over cwd walk" do
    root_a = with_textus
    root_b = File.join(@dir, "other")
    FileUtils.mkdir_p(File.join(root_b, ".textus"))
    result = described_class.resolve(env: { "TEXTUS_ROOT" => root_a }, cwd: root_b)
    expect(result).to eq(root_a)
  end
end
