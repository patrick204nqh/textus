require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Accept do
  def build_store(textus_dir)
    FileUtils.mkdir_p(File.join(textus_dir, "zones/working/network/org"))
    FileUtils.mkdir_p(File.join(textus_dir, "zones/review"))
    File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
        - { name: review, write_policy: [agent, human] }
      entries:
        - { key: working.network.org, path: working/network/org, zone: working, schema: null, owner: o, nested: true, kind: nested}

        - { key: review,             path: review,             zone: review, schema: null, owner: o, nested: true, kind: nested}

    YAML
    Textus::Store.new(textus_dir)
  end

  it "applies the proposal target action and deletes the review entry" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      Textus::Operations.for(store, role: "agent").put(
        "review.2026-05-19-add-bob",
        meta: {
          "name" => "2026-05-19-add-bob",
          "proposal" => { "target_key" => "working.network.org.bob", "action" => "put" },
          "frontmatter" => { "name" => "bob", "org" => "acme" },
        },
        body: "Proposed",
      )

      ctx = test_ctx(role: "human")
      result = build_accept(store, ctx).call("review.2026-05-19-add-bob")

      expect(result["target_key"]).to eq("working.network.org.bob")
      expect(result["action"]).to eq("put")
      expect(result["accepted"]).to eq("review.2026-05-19-add-bob")
      expect(File.exist?(File.join(root, ".textus/zones/working/network/org/bob.md"))).to be true
      expect(File.exist?(File.join(root, ".textus/zones/review/2026-05-19-add-bob.md"))).to be false
    end
  end

  it "raises ProposalError when role is not human" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      Textus::Operations.for(store, role: "agent").put(
        "review.foo",
        meta: {
          "name" => "foo",
          "proposal" => { "target_key" => "working.network.org.x", "action" => "put" },
          "frontmatter" => { "name" => "x" },
        },
        body: "",
      )

      ctx = test_ctx(role: "agent")
      expect { build_accept(store, ctx).call("review.foo") }
        .to raise_error(Textus::ProposalError, /human/)
    end
  end

  it "fires :accepted event with correlation_id" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      Textus::Operations.for(store, role: "agent").put(
        "review.p1",
        meta: {
          "name" => "p1",
          "proposal" => { "target_key" => "working.network.org.alice", "action" => "put" },
          "frontmatter" => { "name" => "alice" },
        },
        body: "Alice content",
      )

      ctx = test_ctx(role: "human", correlation_id: "corr-accept-1")
      events = []
      store.bus.register(:proposal_accepted, :capture_accept) do |ctx:, key:, target_key:, **|
        events << { key: key, target_key: target_key, correlation_id: ctx.correlation_id }
      end

      build_accept(store, ctx).call("review.p1")

      expect(events.length).to eq(1)
      expect(events.first[:key]).to eq("review.p1")
      expect(events.first[:target_key]).to eq("working.network.org.alice")
      expect(events.first[:correlation_id]).to eq("corr-accept-1")
    end
  end

  it "raises ProposalError when entry has no proposal block" do
    Dir.mktmpdir do |root|
      store = build_store(File.join(root, ".textus"))
      Textus::Operations.for(store, role: "agent").put(
        "review.noproposal",
        meta: { "name" => "noproposal" },
        body: "no proposal here",
      )

      ctx = test_ctx(role: "human")
      expect { build_accept(store, ctx).call("review.noproposal") }
        .to raise_error(Textus::ProposalError, /no proposal block/)
    end
  end

  describe "manifest with zero accept_authority roles" do
    def build_zero_authority_store(textus_dir)
      FileUtils.mkdir_p(File.join(textus_dir, "zones/working"))
      FileUtils.mkdir_p(File.join(textus_dir, "zones/review"))
      File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: agent, kind: proposer }
          - { name: runner, kind: runner }
        zones:
          - { name: working, write_policy: [agent, runner] }
          - { name: review, write_policy: [agent] }
        entries:
          - { key: working.n, path: working/n.md, zone: working, schema: null, owner: o, kind: leaf }
          - { key: review, path: review, zone: review, schema: null, owner: o, nested: true, kind: nested }
        rules: []
      YAML
      store = Textus::Store.new(textus_dir)
      Textus::Operations.for(store, role: "agent").put(
        "review.p",
        meta: { "name" => "p", "proposal" => { "target_key" => "working.n", "action" => "put" }, "frontmatter" => { "name" => "n" } },
        body: "b",
      )
      store
    end

    it "accept raises an honest error naming no fallback role" do
      Dir.mktmpdir do |root|
        store = build_zero_authority_store(File.join(root, ".textus"))
        ctx = test_ctx(role: "agent")
        expect { build_accept(store, ctx).call("review.p") }.to raise_error(
          Textus::ProposalError,
          /no role with accept_authority kind is declared/i,
        )
      end
    end

    it "reject raises an honest error naming no fallback role" do
      Dir.mktmpdir do |root|
        store = build_zero_authority_store(File.join(root, ".textus"))
        ctx = test_ctx(role: "agent")
        expect { build_reject(store, ctx).call("review.p") }.to raise_error(
          Textus::ProposalError,
          /no role with accept_authority kind is declared/i,
        )
      end
    end
  end

  describe "promotion gate" do
    def build_store_with_promotion(textus_dir)
      FileUtils.mkdir_p(File.join(textus_dir, "zones/working/network/org"))
      FileUtils.mkdir_p(File.join(textus_dir, "zones/review"))
      FileUtils.mkdir_p(File.join(textus_dir, "schemas"))
      File.write(File.join(textus_dir, "schemas", "org-member.yaml"), <<~YAML)
        name: org-member
        required: [name, org]
        optional: []
        fields: {}
      YAML
      File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner] }
          - { name: review, write_policy: [agent, human] }
        entries:
          - { key: working.network.org, path: working/network/org, zone: working, schema: org-member, owner: o, nested: true, kind: nested}

          - { key: review,             path: review,             zone: review, schema: null, owner: o, nested: true, kind: nested}

        rules:
          - match: "working.network.org.**"
            promotion:
              requires: [schema_valid]
      YAML
      Textus::Store.new(textus_dir)
    end

    it "passes the gate when schema_valid predicate succeeds (all required fields present)" do
      Dir.mktmpdir do |root|
        store = build_store_with_promotion(File.join(root, ".textus"))
        Textus::Operations.for(store, role: "agent").put(
          "review.valid-proposal",
          meta: {
            "name" => "valid-proposal",
            "proposal" => { "target_key" => "working.network.org.carol", "action" => "put" },
            "frontmatter" => { "name" => "carol", "org" => "acme" },
          },
          body: "Proposed",
        )

        ctx = test_ctx(role: "human")
        result = build_accept(store, ctx).call("review.valid-proposal")
        expect(result["accepted"]).to eq("review.valid-proposal")
      end
    end

    it "raises ProposalError when schema_valid predicate fails (missing required field)" do
      Dir.mktmpdir do |root|
        store = build_store_with_promotion(File.join(root, ".textus"))
        Textus::Operations.for(store, role: "agent").put(
          "review.bad-proposal",
          meta: {
            "name" => "bad-proposal",
            "proposal" => { "target_key" => "working.network.org.dave", "action" => "put" },
            "frontmatter" => { "name" => "dave" }, # missing required 'org'
          },
          body: "Proposed",
        )

        ctx = test_ctx(role: "human")
        expect { build_accept(store, ctx).call("review.bad-proposal") }
          .to raise_error(Textus::ProposalError, /promotion gate failed/i)
      end
    end

    def build_human_accept_store(textus_dir)
      FileUtils.mkdir_p(File.join(textus_dir, "zones/working/network/org"))
      FileUtils.mkdir_p(File.join(textus_dir, "zones/review"))
      File.write(File.join(textus_dir, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner] }
          - { name: review, write_policy: [agent, human] }
        entries:
          - { key: working.network.org, path: working/network/org, zone: working, schema: null, owner: o, nested: true, kind: nested}

          - { key: review,             path: review,             zone: review, schema: null, owner: o, nested: true, kind: nested}

        rules:
          - match: "working.network.org.**"
            promotion:
              requires: [human_accept]
      YAML
      Textus::Store.new(textus_dir)
    end

    it "human_accept predicate passes when role is human" do
      Dir.mktmpdir do |root|
        store = build_human_accept_store(File.join(root, ".textus"))
        Textus::Operations.for(store, role: "agent").put(
          "review.ha-proposal",
          meta: {
            "name" => "ha-proposal",
            "proposal" => { "target_key" => "working.network.org.eve", "action" => "put" },
            "frontmatter" => { "name" => "eve" },
          },
          body: "Proposed",
        )
        ctx = test_ctx(role: "human")
        result = build_accept(store, ctx).call("review.ha-proposal")
        expect(result["accepted"]).to eq("review.ha-proposal")
      end
    end
  end
end
