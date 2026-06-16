RSpec.describe Textus::Workflow::Loader do
  include_context "textus_store_fixture"

  it "returns an empty registry when no workflows/ dir exists" do
    registry = described_class.load_all(root)
    expect(registry.all).to be_empty
  end

  it "loads workflow files and registers definitions" do
    FileUtils.mkdir_p(File.join(root, "workflows"))
    File.write(File.join(root, "workflows", "test.rb"), <<~RUBY)
      Textus.workflow "test_wf" do
        match "knowledge.notes.*"
        step(:fetch) { |data, ctx| { content: "loaded" } }
      end
    RUBY

    registry = described_class.load_all(root)
    defn = registry.for("knowledge.notes.x")
    expect(defn).not_to be_nil
    expect(defn.name).to eq("test_wf")
  end
end
