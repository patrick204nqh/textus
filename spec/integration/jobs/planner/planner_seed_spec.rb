# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Jobs::Planner do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge artifacts], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.doc, path: data/knowledge/doc.md, lane: knowledge, kind: leaf }
        - key: artifacts.derived.summary
          path: data/artifacts/derived/summary.json
          lane: artifacts
          kind: produced
          source:
            from: derive
            select: [knowledge.doc]
            transform: identity
    YAML
  end

  let(:queue) { Textus::Ports::JobStore.new(root: store.root) }

  describe ".seed" do
    it "enqueues convergence jobs for the store" do
      described_class.seed(container: store.container, queue: queue, role: "automation")
      expect(queue.ready_ids).not_to be_empty
    end

    it "accepts the caller role as the enqueued_by value" do
      described_class.seed(container: store.container, queue: queue, role: "human")
      leased = queue.lease(worker_id: "test", lease_ttl: 60)
      expect(leased.job.enqueued_by).to eq("human")
    end
  end
end
