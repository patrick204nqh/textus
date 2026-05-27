require "spec_helper"

RSpec.describe "Textus::Manifest role-kind accessors" do
  def parse(yaml)
    Textus::Manifest.parse(yaml)
  end

  describe "default mapping (no roles: block)" do
    let(:m) do
      parse(<<~YAML)
        version: textus/3
        zones:
          - { name: identity, write_policy: [human] }
          - { name: working,  write_policy: [human, agent, runner] }
          - { name: review,   write_policy: [agent] }
          - { name: build,    write_policy: [builder] }
        entries: []
      YAML
    end

    it "maps human → accept_authority" do
      expect(m.role_kind("human")).to eq(:accept_authority)
    end

    it "maps agent → proposer" do
      expect(m.role_kind("agent")).to eq(:proposer)
    end

    it "maps builder → generator" do
      expect(m.role_kind("builder")).to eq(:generator)
    end

    it "maps runner → runner" do
      expect(m.role_kind("runner")).to eq(:runner)
    end

    it "returns nil for unknown role names" do
      expect(m.role_kind("nobody")).to be_nil
    end

    it "lists all roles with a given kind" do
      expect(m.roles_with_kind(:accept_authority)).to eq(["human"])
    end

    it "derives zone kinds from zone writers" do
      expect(m.zone_kinds("review")).to eq(Set[:proposer])
      expect(m.zone_kinds("build")).to eq(Set[:generator])
      expect(m.zone_kinds("working")).to eq(Set[:accept_authority, :proposer, :runner])
    end
  end

  describe "user-declared roles: block" do
    let(:m) do
      parse(<<~YAML)
        version: textus/3
        roles:
          - { name: owner,    kind: accept_authority }
          - { name: compiler, kind: generator }
          - { name: proposer, kind: proposer }
          - { name: fetcher,  kind: runner }
        zones:
          - { name: self,    write_policy: [owner] }
          - { name: world,   write_policy: [fetcher] }
          - { name: memory,  write_policy: [proposer, owner] }
          - { name: library, write_policy: [proposer] }
          - { name: build,   write_policy: [compiler] }
        entries: []
      YAML
    end

    it "honors the declared mapping" do
      expect(m.role_kind("owner")).to eq(:accept_authority)
      expect(m.role_kind("compiler")).to eq(:generator)
      expect(m.role_kind("proposer")).to eq(:proposer)
      expect(m.role_kind("fetcher")).to eq(:runner)
    end

    it "does not fall back to defaults when roles: is declared" do
      expect(m.role_kind("human")).to be_nil
      expect(m.role_kind("builder")).to be_nil
    end

    it "derives zone kinds from declared roles" do
      expect(m.zone_kinds("library")).to eq(Set[:proposer])
      expect(m.zone_kinds("build")).to eq(Set[:generator])
      expect(m.zone_kinds("memory")).to eq(Set[:proposer, :accept_authority])
    end
  end

  describe "empty roles: []" do
    it "treats every role as undeclared" do
      # An empty roles: block + no writers means schema is valid but the mapping is empty.
      m = parse(<<~YAML)
        version: textus/3
        roles: []
        zones:
          - { name: identity, write_policy: [] }
        entries: []
      YAML
      expect(m.role_kind("anyone")).to be_nil
      expect(m.roles_with_kind(:accept_authority)).to eq([])
    end
  end
end
