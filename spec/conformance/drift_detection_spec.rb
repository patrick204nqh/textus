require "spec_helper"

# Conformance fixture D from textus/4 §12 after doctor-class migration.
RSpec.describe "textus/4 conformance — Fixture D: generator drift detection" do
  include_context "textus/4 conformance fixture"

  describe "Fixture D — generator drift detection migration" do
    it "keeps doctor callable while drift moved to workflow artifacts" do
      artifacts_path = File.join(root, "data/artifacts/catalogs/skills.md")
      File.write(artifacts_path, <<~MD)
        ---
        generated:
          by: "rake catalog:skills"
          at: "2020-01-01T00:00:00Z"
          from:
            - knowledge.projects
        ---
        catalog body
      MD

      project_path = File.join(root, "data/knowledge/projects/acme.md")
      File.write(project_path, "---\nname: acme\n---\nproject body\n")
      File.utime(Time.now, Time.now, project_path)

      res = store.with_role(Textus::Value::Role::DEFAULT).doctor
      expect(res["protocol"]).to eq(Textus::PROTOCOL)
      expect(res).to have_key("issues")
    end
  end
end
