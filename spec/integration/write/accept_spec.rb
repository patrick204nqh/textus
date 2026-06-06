require "spec_helper"

RSpec.describe Textus::Write::Accept do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: ["knowledge/network/org", "proposals"], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: proposals,  kind: queue }
      entries:
        - { key: knowledge.network.org, path: knowledge/network/org, zone: knowledge, owner: human:self, kind: nested }
        - { key: proposals, path: proposals, zone: proposals, owner: human:self, kind: nested }
    YAML
  end

  it "applies the proposal target action and deletes the proposals entry" do
    store.as("agent").put(
      "proposals.2026-05-19-add-bob",
      meta: {
        "name" => "2026-05-19-add-bob",
        "proposal" => { "target_key" => "knowledge.network.org.bob", "action" => "put" },
        "frontmatter" => { "name" => "bob", "org" => "acme" },
      },
      body: "Proposed",
    )

    result = store.as("human").accept("proposals.2026-05-19-add-bob")

    expect(result["target_key"]).to eq("knowledge.network.org.bob")
    expect(result["action"]).to eq("put")
    expect(result["accepted"]).to eq("proposals.2026-05-19-add-bob")
    expect(File.exist?(File.join(root, "zones/knowledge/network/org/bob.md"))).to be(true)
    expect(File.exist?(File.join(root, "zones/proposals/2026-05-19-add-bob.md"))).to be(false)
  end

  it "refuses a non-authority actor with guard_failed naming the predicate" do
    store.as("agent").put(
      "proposals.foo",
      meta: {
        "name" => "foo",
        "proposal" => { "target_key" => "knowledge.network.org.x", "action" => "put" },
        "frontmatter" => { "name" => "x" },
      },
      body: "",
    )

    expect { store.as("agent").accept("proposals.foo") }
      .to fail_guard_with("author_held")
  end

  it "fires :accepted event with correlation_id" do
    store.as("agent").put(
      "proposals.p1",
      meta: {
        "name" => "p1",
        "proposal" => { "target_key" => "knowledge.network.org.alice", "action" => "put" },
        "frontmatter" => { "name" => "alice" },
      },
      body: "Alice content",
    )

    events = []
    store.events.register(:proposal_accepted, :capture_accept) do |ctx:, key:, target_key:, **|
      events << { key: key, target_key: target_key, correlation_id: ctx.correlation_id }
    end

    store.as("human", correlation_id: "corr-accept-1").accept("proposals.p1")

    expect(events.length).to eq(1)
    expect(events.first[:key]).to eq("proposals.p1")
    expect(events.first[:target_key]).to eq("knowledge.network.org.alice")
    expect(events.first[:correlation_id]).to eq("corr-accept-1")
  end

  it "raises ProposalError when entry has no proposal block" do
    store.as("agent").put("proposals.noproposal", meta: { "name" => "noproposal" }, body: "no proposal here")

    expect { store.as("human").accept("proposals.noproposal") }
      .to raise_error(Textus::ProposalError, /no proposal block/)
  end

  describe "manifest with no role holding the author capability" do
    # No role holds `author`: agent only proposes, automation only fetches.
    # proposals is a queue (propose), feeds is quarantine (fetch) so the
    # manifest still validates — yet accept/reject have no authority to gate.
    let(:store) do
      s = store_from_manifest(root, zones: %w[feeds proposals], manifest: <<~YAML)
        version: textus/3
        roles:
          - { name: agent, can: [propose] }
          - { name: automation, can: [reconcile] }
        zones:
          - { name: feeds, kind: quarantine }
          - { name: proposals, kind: queue }
        entries:
          - { key: feeds.n, path: feeds/n.md, zone: feeds, owner: human:self, kind: leaf }
          - { key: proposals, path: proposals, zone: proposals, owner: human:self, kind: nested }
        rules: []
      YAML
      s.as("agent").put(
        "proposals.p",
        meta: { "name" => "p", "proposal" => { "target_key" => "feeds.n", "action" => "put" }, "frontmatter" => { "name" => "n" } },
        body: "b",
      )
      s
    end

    it "accept raises an honest error that the author capability is unheld" do
      expect { store.as("agent").accept("proposals.p") }
        .to raise_error(Textus::GuardFailed, /no role holds the 'author' capability.*accept is disabled/i)
    end

    it "reject raises an honest error that the author capability is unheld" do
      expect { store.as("agent").reject("proposals.p") }
        .to raise_error(Textus::GuardFailed, /no role holds the 'author' capability.*reject is disabled/i)
    end
  end

  describe "promotion gate" do
    context "with a schema_valid guard" do
      let(:org_member_schema) do
        <<~SCHEMA
          name: org-member
          required: [name, org]
          optional: []
          fields: {}
        SCHEMA
      end

      let(:store) do
        store_from_manifest(
          root,
          zones: ["knowledge/network/org", "proposals"],
          schemas: { "org-member" => org_member_schema },
          manifest: <<~YAML,
            version: textus/3
            zones:
              - { name: knowledge, kind: canon }
              - { name: proposals,  kind: queue }
            entries:
              - { key: knowledge.network.org, path: knowledge/network/org, zone: knowledge, schema: org-member, owner: human:self, kind: nested }
              - { key: proposals, path: proposals, zone: proposals, owner: human:self, kind: nested }
            rules:
              - match: "knowledge.network.org.**"
                guard:
                  accept: [schema_valid]
          YAML
        )
      end

      it "passes the gate when schema_valid succeeds (all required fields present)" do
        store.as("agent").put(
          "proposals.valid-proposal",
          meta: {
            "name" => "valid-proposal",
            "proposal" => { "target_key" => "knowledge.network.org.carol", "action" => "put" },
            "frontmatter" => { "name" => "carol", "org" => "acme" },
          },
          body: "Proposed",
        )

        result = store.as("human").accept("proposals.valid-proposal")
        expect(result["accepted"]).to eq("proposals.valid-proposal")
      end

      it "raises guard_failed when schema_valid fails (missing required field)" do
        store.as("agent").put(
          "proposals.bad-proposal",
          meta: {
            "name" => "bad-proposal",
            "proposal" => { "target_key" => "knowledge.network.org.dave", "action" => "put" },
            "frontmatter" => { "name" => "dave" }, # missing required 'org'
          },
          body: "Proposed",
        )

        expect { store.as("human").accept("proposals.bad-proposal") }
          .to fail_guard_with("schema_valid")
      end
    end

    context "with an author_held guard" do
      let(:store) do
        store_from_manifest(root, zones: ["knowledge/network/org", "proposals"], manifest: <<~YAML)
          version: textus/3
          zones:
            - { name: knowledge, kind: canon }
            - { name: proposals,  kind: queue }
          entries:
            - { key: knowledge.network.org, path: knowledge/network/org, zone: knowledge, owner: human:self, kind: nested }
            - { key: proposals, path: proposals, zone: proposals, owner: human:self, kind: nested }
          rules:
            - match: "knowledge.network.org.**"
              guard:
                accept: [author_held]
        YAML
      end

      it "passes when the role holds the author capability" do
        store.as("agent").put(
          "proposals.ha-proposal",
          meta: {
            "name" => "ha-proposal",
            "proposal" => { "target_key" => "knowledge.network.org.eve", "action" => "put" },
            "frontmatter" => { "name" => "eve" },
          },
          body: "Proposed",
        )

        result = store.as("human").accept("proposals.ha-proposal")
        expect(result["accepted"]).to eq("proposals.ha-proposal")
      end
    end
  end
end
