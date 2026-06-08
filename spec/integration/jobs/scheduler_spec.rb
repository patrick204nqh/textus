require "spec_helper"

RSpec.describe Textus::Jobs::Scheduler do
  include_context "textus_store_fixture"
  include_context "intake doc" # provides `store` with a stale-on-boot intake entry (machine.doc)

  let(:queue) { Textus::Ports::Queue.new(root: root) }

  def run_once
    store # boot the intake-wired store
    described_class.new(container: store.container, queue: queue).run_once
  end

  it "enqueues a re-pull job for each stale intake key" do
    run_once
    expect(queue.ready_ids).to include(a_string_starting_with("re-pull:"))
  end

  it "enqueues a single sweep job per run" do
    run_once
    expect(queue.ready_ids.count { |i| i.start_with?("sweep:") }).to eq(1)
  end
end
