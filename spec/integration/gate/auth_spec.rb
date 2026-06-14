# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Gate::Auth do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge proposals feeds], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
        - { name: proposals, kind: queue }
        - { name: feeds,     kind: machine }
      entries:
        - { key: knowledge.doc,   path: data/knowledge/doc.md,   lane: knowledge, kind: leaf }
        - { key: proposals,       path: proposals,                lane: proposals, owner: human:self, kind: nested }
        - { key: feeds.data,      path: data/feeds/data.md,      lane: feeds,     kind: leaf }
    YAML
  end

  it "raises UsageError for an unmapped command class" do
    unknown = Class.new(Struct.new(:role, :key)) { def self.name = "Textus::Command::Ghost" }
    cmd = unknown.new("human", "knowledge.doc")
    auth = Textus::Gate::Auth.new(store.container)
    expect { auth.check!(cmd) }.to raise_error(Textus::UsageError, /unmapped command/)
  end

  describe "AUTOMATION role" do
    it "is blocked from writing to a canon lane" do
      expect { store.as("automation").put("knowledge.doc", meta: {}, body: "x") }
        .to raise_error(Textus::WriteForbidden)
    end

    it "is permitted to write to a machine lane" do
      expect { store.as("automation").put("feeds.data", meta: {}, body: "x") }
        .not_to raise_error
    end
  end

  describe "propose auth via Gate" do
    it "blocks a role without propose capability" do
      expect { store.as("automation").propose("decisions.x", body: "hi") }
        .to raise_error(Textus::Error)
    end

    it "permits a role with propose capability" do
      expect { store.as("agent").propose("decisions.x", body: "hi") }
        .not_to raise_error
    end

    it "does not pass pending_key through to Action::Propose" do
      expect { store.as("agent").propose("decisions.x", body: "hi") }
        .not_to raise_error(ArgumentError)
    end
  end

  describe "accept FLOOR check" do
    it "blocks a role without author capability (author_held from FLOOR)" do
      store.as("agent").put(
        "proposals.foo",
        meta: { "proposal" => { "target_key" => "knowledge.doc", "action" => "put" } },
        body: "proposed",
      )
      expect { store.as("agent").accept("proposals.foo") }
        .to fail_guard_with("author_held")
    end

    it "permits a role with author capability" do
      store.as("agent").put(
        "proposals.bar",
        meta: { "proposal" => { "target_key" => "knowledge.doc", "action" => "put" } },
        body: "proposed",
      )
      expect { store.as("human").accept("proposals.bar") }.not_to raise_error
    end
  end

  describe "RoleScope verb dispatch" do
    it "dispatches through Gate when called via store.as(role).verb" do
      expect { store.as("human").put("knowledge.doc", meta: {}, body: "x") }
        .not_to raise_error
    end

    it "preserves correlation_id across verb calls on the same scope" do
      scope = store.as("human", correlation_id: "test-corr-id")
      scope.put("knowledge.doc", meta: {}, body: "first")
      expect(scope.correlation_id).to eq("test-corr-id")
    end

    it "does not pass pending_key through to Action::Propose" do
      expect { store.as("agent").propose("decisions.x", body: "hi") }
        .not_to raise_error(ArgumentError)
    end
  end

  describe "Doctor::Check#dispatch role threading" do
    it "dispatches as the caller's role, not always human" do
      recorded = []
      check_class = Class.new(Textus::Doctor::Check) do
        define_method(:call) do
          dispatch(:list, prefix: nil, lane: nil)
          recorded << @role
          []
        end
      end
      check = check_class.new(store.container, role: "agent")
      check.call
      expect(recorded).to eq(["agent"])
    end
  end
end
