require "spec_helper"

RSpec.describe Textus::Store::Geometry do
  subject(:sg) { described_class.new("/tmp/store/.textus") }

  describe "data paths" do
    it "exposes data root" do
      expect(sg.data_root).to eq("/tmp/store/.textus/data")
    end

    it "exposes lane path" do
      expect(sg.lane_path("knowledge")).to eq("/tmp/store/.textus/data/knowledge")
    end

    it "resolves an entry path with extension" do
      mentry = instance_double("Textus::Manifest::Entry::Base",
        path: "knowledge/note",
        format: "markdown")
      allow(Textus::Format).to receive_message_chain(:for, :extensions).and_return([".md"])
      expect(sg.entry_path(mentry)).to eq("/tmp/store/.textus/data/knowledge/note.md")
    end

    it "resolves an entry path with existing extension" do
      mentry = instance_double("Textus::Manifest::Entry::Base",
        path: "data/knowledge/note.md",
        format: "markdown")
      expect(sg.entry_path(mentry)).to eq("/tmp/store/.textus/data/knowledge/note.md")
    end
  end

  describe "runtime paths" do
    it "nests under .state/" do
      expect(sg.run_root).to eq("/tmp/store/.textus/.state")
      expect(sg.cursor_path("agent")).to eq("/tmp/store/.textus/.state/cursors/agent")
      expect(sg.lock_path("build")).to eq("/tmp/store/.textus/.state/locks/build.lock")
      expect(sg.audit_log_path).to eq("/tmp/store/.textus/.state/audit/audit.log")
      expect(sg.sentinels_root).to eq("/tmp/store/.textus/.state/sentinels")
      expect(sg.store_db_path).to eq("/tmp/store/.textus/.state/store.db")
    end
  end

  describe "asset paths" do
    it "builds dated asset paths" do
      expect(sg.asset_path("raw", "2026/06/20", "screenshots", "test.png"))
        .to eq("/tmp/store/.textus/assets/raw/2026/06/20/screenshots/test.png")
    end
  end

  describe "config paths" do
    it "exposes schema, template, workflow, manifest paths" do
      expect(sg.manifest_path).to eq("/tmp/store/.textus/manifest.yaml")
      expect(sg.schema_path("project")).to eq("/tmp/store/.textus/schemas/project.yaml")
      expect(sg.template_path("orientation.erb")).to eq("/tmp/store/.textus/templates/orientation.erb")
      expect(sg.workflow_dir).to eq("/tmp/store/.textus/workflows")
    end
  end

  describe "gitignore" do
    it "generates gitignore body with .state/ always ignored" do
      body = sg.gitignore_body
      expect(body).to include(".state/")
    end

    it "includes untracked entry paths" do
      body = sg.gitignore_body(untracked_entries: ["data/artifacts/feeds/machines/"])
      expect(body).to include("data/artifacts/feeds/machines/")
    end
  end

  describe "lane boundary" do
    it "returns lane floor for a path under data/" do
      expect(sg.lane_floor("/tmp/store/.textus/data/knowledge/note.md"))
        .to eq("/tmp/store/.textus/data/knowledge")
    end

    it "returns nil for a path outside data/" do
      expect(sg.lane_floor("/tmp/store/.textus/.state/store.db")).to be_nil
    end
  end
end
