RSpec.describe Textus::Workflow::Loader do
  include_context "textus_store_fixture"

  it "returns an empty array when no workflows/ dir exists" do
    defns = described_class.load_all(root)
    expect(defns).to be_empty
  end

  it "loads workflow files and registers definitions" do
    FileUtils.mkdir_p(File.join(root, "workflows"))
    File.write(File.join(root, "workflows", "test.rb"), <<~RUBY)
      Textus.workflow "test_wf" do
        match "knowledge.notes.*"
        step :fetch do |_data, _ctx|
          { content: "loaded" }
        end
      end
    RUBY

    defns = described_class.load_all(root)
    defn = defns.find { |d| d.match?("knowledge.notes.x") }
    expect(defn).not_to be_nil
    expect(defn.name).to eq("test_wf")
  end
end
