require "spec_helper"

RSpec.describe Textus::StoreGeometry do
  let(:root) { "/tmp/store/.textus" }
  subject    { described_class.new(root) }

  it "nests runtime paths under .state/" do
    expect(subject.run_root).to eq("/tmp/store/.textus/.state")
    expect(subject.cursor_path("agent")).to eq("/tmp/store/.textus/.state/cursors/agent")
    expect(subject.lock_path("build")).to eq("/tmp/store/.textus/.state/locks/build.lock")
    expect(subject.lock_path("watcher")).to eq("/tmp/store/.textus/.state/locks/watcher.lock")
    expect(subject.audit_dir_path).to eq("/tmp/store/.textus/.state/audit")
    expect(subject.audit_log_path).to eq("/tmp/store/.textus/.state/audit/audit.log")
  end

  it "exposes sentinel paths under .state/" do
    expect(subject.sentinels_root).to eq("/tmp/store/.textus/.state/sentinels")
  end

  it "exposes data paths under .textus/data" do
    expect(subject.data_root).to eq("/tmp/store/.textus/data")
    expect(subject.lane_path("knowledge")).to eq("/tmp/store/.textus/data/knowledge")
  end

  it "stores the SQLite database under the runtime subtree" do
    expect(described_class.new("/tmp/store/.textus").store_db_path).to eq("/tmp/store/.textus/.state/store.db")
  end

  it "exposes a .gitignore body that ignores the state subtree" do
    expect(subject.gitignore_body).to include(".state/\n")
  end
end
