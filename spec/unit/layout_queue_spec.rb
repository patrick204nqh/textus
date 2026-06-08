require "spec_helper"

RSpec.describe Textus::Layout do
  let(:root) { "/tmp/store/.textus" }

  it "nests the queue under the runtime subtree" do
    expect(described_class.queue(root)).to eq("/tmp/store/.textus/.run/queue")
  end

  it "exposes a subdir per job state" do
    expect(described_class.queue_state(root, :ready)).to eq("/tmp/store/.textus/.run/queue/ready")
    expect(described_class.queue_state(root, :leased)).to eq("/tmp/store/.textus/.run/queue/leased")
    expect(described_class.queue_state(root, :done)).to eq("/tmp/store/.textus/.run/queue/done")
    expect(described_class.queue_state(root, :failed)).to eq("/tmp/store/.textus/.run/queue/failed")
  end
end
