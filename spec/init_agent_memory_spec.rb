require "spec_helper"
require "tmpdir"

RSpec.describe "a freshly init'd store delivers the agent-memory promise (ADR 0033)" do
  it "lets the agent write its notebook without a human accept" do
    Dir.mktmpdir do |dir|
      dot = File.join(dir, ".textus")
      Textus::Init.run(dot)
      store = Textus::Store.new(dot)
      store.as("agent").put("notebook.notes.s1", meta: { "name" => "s1" }, body: "remembered\n")
      expect(store.as("agent").get("notebook.notes.s1").body).to eq("remembered\n")
    end
  end
end
