# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Jobs::Planner do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge artifacts], manifest: <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.doc, path: knowledge/doc.md, lane: knowledge, kind: leaf }
        - key: artifacts.derived.summary
          path: artifacts/derived/summary.json
          lane: artifacts
          kind: produced
          source: { from: external, command: "make", sources: [] }
    YAML
  end

  let(:store_port) { Textus::Port::Store.new(root: store.root).setup! }
  let(:queue) { Textus::Jobs::Queue.new(store: store_port) }

  after { store_port.close }

  describe ".seed" do
    it "enqueues convergence jobs for the store" do
      described_class.seed(container: store.container, queue: queue, role: "automation")
      expect(queue.ready_ids).not_to be_empty
    end

    it "accepts the caller role as the role value" do
      described_class.seed(container: store.container, queue: queue, role: "human")
      leased = queue.lease(worker_id: "test", lease_ttl: 60)
      expect(leased.job.role).to eq("human")
    end
  end
end
