require "spec_helper"

RSpec.describe Textus::Layout do
  let(:root) { "/tmp/store/.textus" }

  it "nests every runtime path under .run/" do
    expect(described_class.run(root)).to eq("/tmp/store/.textus/.run")
    expect(described_class.state(root)).to eq("/tmp/store/.textus/.run/state")
    expect(described_class.cursor(root, "agent")).to eq("/tmp/store/.textus/.run/state/cursor.agent")
    expect(described_class.locks(root)).to eq("/tmp/store/.textus/.run/locks")
    expect(described_class.build_lock(root)).to eq("/tmp/store/.textus/.run/build.lock")
    expect(described_class.audit_dir(root)).to eq("/tmp/store/.textus/.run/audit")
    expect(described_class.audit_log(root)).to eq("/tmp/store/.textus/.run/audit/audit.log")
  end

  it "exposes data paths under .textus/data" do
    expect(described_class.data(root)).to eq("/tmp/store/.textus/data")
    expect(described_class.data_lane(root, "knowledge")).to eq("/tmp/store/.textus/data/knowledge")
  end

  it "exposes a .gitignore body that ignores the run subtree" do
    expect(described_class::GITIGNORE).to include(".run/\n")
    expect(described_class.gitignore_body).to include(".run/\n")
  end
end
