require "spec_helper"

RSpec.describe Textus::Write::Accept do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: ["working/network/org", "review"], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
        - { name: review,  kind: queue }
      entries:
        - { key: working.network.org, path: working/network/org, zone: working, schema: null, owner: o, nested: true, kind: nested }
        - { key: review, path: review, zone: review, schema: null, owner: o, nested: true, kind: nested }
    YAML
  end

  it "applies the proposal target action and deletes the review entry" do
    store.as("agent").put(
      "review.2026-05-19-add-bob",
      meta: {
        "name" => "2026-05-19-add-bob",
        "proposal" => { "target_key" => "working.network.org.bob", "action" => "put" },
        "frontmatter" => { "name" => "bob", "org" => "acme" },
      },
      body: "Proposed",
    )

    result = store.as("human").accept("review.2026-05-19-add-bob")

    expect(result["target_key"]).to eq("working.network.org.bob")
    expect(result["action"]).to eq("put")
    expect(result["accepted"]).to eq("review.2026-05-19-add-bob")
    expect(File.exist?(File.join(root, "zones/working/network/org/bob.md"))).to be(true)
    expect(File.exist?(File.join(root, "zones/review/2026-05-19-add-bob.md"))).to be(false)
  end

  it "refuses a non-authority actor with guard_failed naming the predicate" do
    store.as("agent").put(
      "review.foo",
      meta: {
        "name" => "foo",
        "proposal" => { "target_key" => "working.network.org.x", "action" => "put" },
        "frontmatter" => { "name" => "x" },
      },
      body: "",
    )

    expect { store.as("agent").accept("review.foo") }
      .to fail_guard_with("author_held")
  end

  it "fires :accepted event with correlation_id" do
    store.as("agent").put(
      "review.p1",
      meta: {
        "name" => "p1",
        "proposal" => { "target_key" => "working.network.org.alice", "action" => "put" },
        "frontmatter" => { "name" => "alice" },
      },
      body: "Alice content",
    )

    events = []
    store.events.register(:proposal_accepted, :capture_accept) do |ctx:, key:, target_key:, **|
      events << { key: key, target_key: target_key, correlation_id: ctx.correlation_id }
    end

    store.as("human", correlation_id: "corr-accept-1").accept("review.p1")

    expect(events.length).to eq(1)
    expect(events.first[:key]).to eq("review.p1")
    expect(events.first[:target_key]).to eq("working.network.org.alice")
    expect(events.first[:correlation_id]).to eq("corr-accept-1")
  end

  it "raises ProposalError when entry has no proposal block" do
    store.as("agent").put("review.noproposal", meta: { "name" => "noproposal" }, body: "no proposal here")

    expect { store.as("human").accept("review.noproposal") }
      .to raise_error(Textus::ProposalError, /no proposal block/)
  end

  describe "manifest with no role holding the author capability" do
    # No role holds `author`: agent only proposes, automation only fetches.
    # review is a queue (propose), working is quarantine (fetch) so the
    # manifest still validates — yet accept/reject have no authority to gate.
    let(:store) do
      s = store_from_manifest(root, zones: %w[working review], manifest: <<~YAML)
        version: textus/3
        roles:
          - { name: agent, can: [propose] }
          - { name: automation, can: [fetch] }
        zones:
          - { name: working, kind: quarantine }
          - { name: review, kind: queue }
        entries:
          - { key: working.n, path: working/n.md, zone: working, schema: null, owner: o, kind: leaf }
          - { key: review, path: review, zone: review, schema: null, owner: o, nested: true, kind: nested }
        rules: []
      YAML
      s.as("agent").put(
        "review.p",
        meta: { "name" => "p", "proposal" => { "target_key" => "working.n", "action" => "put" }, "frontmatter" => { "name" => "n" } },
        body: "b",
      )
      s
    end

    it "accept raises an honest error that the author capability is unheld" do
      expect { store.as("agent").accept("review.p") }
        .to raise_error(Textus::GuardFailed, /no role holds the 'author' capability.*accept is disabled/i)
    end

    it "reject raises an honest error that the author capability is unheld" do
      expect { store.as("agent").reject("review.p") }
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
          zones: ["working/network/org", "review"],
          schemas: { "org-member" => org_member_schema },
          manifest: <<~YAML,
            version: textus/3
            zones:
              - { name: working, kind: canon }
              - { name: review,  kind: queue }
            entries:
              - { key: working.network.org, path: working/network/org, zone: working, schema: org-member, owner: o, nested: true, kind: nested }
              - { key: review, path: review, zone: review, schema: null, owner: o, nested: true, kind: nested }
            rules:
              - match: "working.network.org.**"
                guard:
                  accept: [schema_valid]
          YAML
        )
      end

      it "passes the gate when schema_valid succeeds (all required fields present)" do
        store.as("agent").put(
          "review.valid-proposal",
          meta: {
            "name" => "valid-proposal",
            "proposal" => { "target_key" => "working.network.org.carol", "action" => "put" },
            "frontmatter" => { "name" => "carol", "org" => "acme" },
          },
          body: "Proposed",
        )

        result = store.as("human").accept("review.valid-proposal")
        expect(result["accepted"]).to eq("review.valid-proposal")
      end

      it "raises guard_failed when schema_valid fails (missing required field)" do
        store.as("agent").put(
          "review.bad-proposal",
          meta: {
            "name" => "bad-proposal",
            "proposal" => { "target_key" => "working.network.org.dave", "action" => "put" },
            "frontmatter" => { "name" => "dave" }, # missing required 'org'
          },
          body: "Proposed",
        )

        expect { store.as("human").accept("review.bad-proposal") }
          .to fail_guard_with("schema_valid")
      end
    end

    context "with an author_held guard" do
      let(:store) do
        store_from_manifest(root, zones: ["working/network/org", "review"], manifest: <<~YAML)
          version: textus/3
          zones:
            - { name: working, kind: canon }
            - { name: review,  kind: queue }
          entries:
            - { key: working.network.org, path: working/network/org, zone: working, schema: null, owner: o, nested: true, kind: nested }
            - { key: review, path: review, zone: review, schema: null, owner: o, nested: true, kind: nested }
          rules:
            - match: "working.network.org.**"
              guard:
                accept: [author_held]
        YAML
      end

      it "passes when the role holds the author capability" do
        store.as("agent").put(
          "review.ha-proposal",
          meta: {
            "name" => "ha-proposal",
            "proposal" => { "target_key" => "working.network.org.eve", "action" => "put" },
            "frontmatter" => { "name" => "eve" },
          },
          body: "Proposed",
        )

        result = store.as("human").accept("review.ha-proposal")
        expect(result["accepted"]).to eq("review.ha-proposal")
      end
    end
  end
end
