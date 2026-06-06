require "spec_helper"

# Conformance for store#validate_all over the textus/3 §12 fixture.
RSpec.describe "textus/3 conformance — store#validate_all" do
  include_context "textus/3 conformance fixture"

  describe "store#validate_all" do
    it "returns ok when every entry conforms" do
      res = store.as(Textus::Role::DEFAULT).validate_all
      expect(res["ok"]).to be true
      expect(res["violations"]).to be_empty
    end

    it "reports schema violations and bad frontmatter" do
      File.write(File.join(root, "zones/knowledge/network/org/broken.md"),
                 "---\nname: broken\n---\n")
      res = store.as(Textus::Role::DEFAULT).validate_all
      expect(res["ok"]).to be false
      keys = res["violations"].map { |v| v["key"] }
      expect(keys).to include("knowledge.network.org.broken")
    end
  end
end
