require "spec_helper"

RSpec.describe Textus::Layout do
  let(:root) { "/tmp/store/.textus" }

  it "nests every runtime path under .state/" do
    expect(described_class.run(root)).to eq("/tmp/store/.textus/.state")
    expect(described_class.cursors(root)).to eq("/tmp/store/.textus/.state/cursors")
    expect(described_class.cursor(root, "agent")).to eq("/tmp/store/.textus/.state/cursors/agent")
    expect(described_class.locks(root)).to eq("/tmp/store/.textus/.state/locks")
    expect(described_class.build_lock(root)).to eq("/tmp/store/.textus/.state/build.lock")
    expect(described_class.watcher_lock(root)).to eq("/tmp/store/.textus/.state/watcher.lock")
    expect(described_class.audit_dir(root)).to eq("/tmp/store/.textus/.state/audit")
    expect(described_class.audit_log(root)).to eq("/tmp/store/.textus/.state/audit/audit.log")
  end

  it "exposes sentinel paths under .state/" do
    expect(described_class.sentinels(root)).to eq("/tmp/store/.textus/.state/sentinels")
  end

  it "exposes data paths under .textus/data" do
    expect(described_class.data(root)).to eq("/tmp/store/.textus/data")
    expect(described_class.data_lane(root, "knowledge")).to eq("/tmp/store/.textus/data/knowledge")
  end

  it "stores the SQLite database under the runtime subtree" do
    expect(described_class.store_db("/tmp/store/.textus")).to eq("/tmp/store/.textus/.state/store.db")
  end

  it "exposes a .gitignore body that ignores the state subtree" do
    expect(described_class::GITIGNORE).to include(".state/\n")
    expect(described_class.gitignore_body).to include(".state/\n")
  end
end
