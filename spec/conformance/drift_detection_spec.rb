require "spec_helper"

# Conformance fixture D from textus/3 §12: generator drift detection (via doctor).
RSpec.describe "textus/3 conformance — Fixture D: generator drift detection" do
  include_context "textus/3 conformance fixture"

  describe "Fixture D — generator drift detection (via doctor)" do
    it "flags artifacts entries with sources newer than generated.at without executing" do
      artifacts_path = File.join(root, "zones/artifacts/catalogs/skills.md")
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

      project_path = File.join(root, "zones/knowledge/projects/acme.md")
      File.write(project_path, "---\nname: acme\n---\nproject body\n")
      File.utime(Time.now, Time.now, project_path)

      drift = store.as(Textus::Role::DEFAULT).doctor["issues"]
                   .select { |i| i["code"] == "generator_drift" }
      expect(drift.length).to eq(1)
      row = drift.first
      expect(row["subject"]).to eq("artifacts.catalogs.skills")
      expect(row["message"]).to match(/knowledge\.projects/)
    end
  end
end
