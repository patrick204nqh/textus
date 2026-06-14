# frozen_string_literal: true

require "pathname"

# Unit examples for the pure SpecLayout helper, plus the live guard that uses it
# to assert every constant-described spec mirrors lib/textus/. This file's own
# top-level group is `SpecLayout` (not a Textus:: constant), so the sweep below
# treats it as exempt.
RSpec.describe SpecLayout do
  describe ".described_constant" do
    it "extracts a Textus constant from a class-described spec" do
      src = "RSpec.describe Textus::Ports::BuildLock do\nend\n"
      expect(described_class.described_constant(src)).to eq("Textus::Ports::BuildLock")
    end

    it "returns the leading constant when describe has extra arguments" do
      src = %(RSpec.describe Textus::Store, ".discover" do\nend\n)
      expect(described_class.described_constant(src)).to eq("Textus::Store")
    end

    it "returns nil for a string-described (integration) spec" do
      src = %(RSpec.describe "feeds.machines end-to-end" do\nend\n)
      expect(described_class.described_constant(src)).to be_nil
    end

    it "returns nil for a non-Textus constant" do
      src = "RSpec.describe SomeHelper do\nend\n"
      expect(described_class.described_constant(src)).to be_nil
    end
  end

  describe ".normalize" do
    it "lowercases and strips underscores so dir and constant segments compare" do
      expect(described_class.normalize("BuildLock")).to eq("buildlock")
      expect(described_class.normalize("build_lock")).to eq("buildlock")
      expect(described_class.normalize("MCP")).to eq("mcp")
    end
  end

  describe ".placement_error" do
    it "passes a nested unit spec sitting in its namespace dir" do
      expect(described_class.placement_error("Textus::Ports::BuildLock", ["ports"])).to be_nil
    end

    it "flags a nested unit spec sitting flat at the spec root" do
      expect(described_class.placement_error("Textus::Ports::BuildLock", [])).not_to be_nil
    end

    it "passes a module-grouping spec living in its own dir" do
      expect(described_class.placement_error("Textus::Manifest", ["manifest"])).to be_nil
    end

    it "passes a module-grouping spec living at the spec root" do
      expect(described_class.placement_error("Textus::Manifest", [])).to be_nil
    end

    it "flags a deeply-namespaced spec that is one dir too shallow" do
      const = "Textus::Doctor::Check::OrphanedPublishTargets"
      expect(described_class.placement_error(const, ["doctor"])).not_to be_nil
      expect(described_class.placement_error(const, %w[doctor check])).to be_nil
    end
  end

  describe ".string_described? / .store_backed?" do
    it "detects a string-described (conformance) top-level group" do
      expect(described_class.string_described?(%(RSpec.describe "x end-to-end" do\nend))).to be(true)
      expect(described_class.string_described?("RSpec.describe Textus::Store do\nend")).to be(false)
    end

    it "detects a store-backed (integration) spec" do
      expect(described_class.store_backed?("include_context \"textus_store_fixture\"")).to be(true)
      expect(described_class.store_backed?("minimal_store(root)")).to be(true)
      expect(described_class.store_backed?("expect(1).to eq(1)")).to be(false)
    end
  end

  # The live rule: a category segment (unit/integration/conformance) wraps the
  # lib/-mirror. The sweep below uses this.
  describe ".categorized_placement_error" do
    it "passes a unit spec mirrored below its category" do
      expect(described_class.categorized_placement_error("Textus::Ports::BuildLock", %w[unit ports])).to be_nil
    end

    it "passes an integration spec mirrored below its category" do
      expect(described_class.categorized_placement_error("Textus::Dispatch::Actions::Get", %w[integration dispatch actions])).to be_nil
    end

    it "flags a spec sitting at the spec root (no category)" do
      expect(described_class.categorized_placement_error("Textus::Dispatch::Actions::Get", [])).not_to be_nil
    end

    it "flags an unknown leading segment that is not a category" do
      err = described_class.categorized_placement_error("Textus::Dispatch::Actions::Get", %w[read])
      expect(err).to match(/not a category/)
    end

    it "flags a misfiled spec under the wrong mirror dir within a category" do
      expect(described_class.categorized_placement_error("Textus::Ports::BuildLock", %w[unit read])).not_to be_nil
    end
  end

  # The live guard, post-split. This file lives in spec/unit/, so the spec root
  # is one level up. Every spec must sit under a category; constant-described
  # specs mirror lib/ inside it; string-described specs are conformance; unit
  # specs stay pure. (A non-Textus-constant describe — like this file's own
  # `SpecLayout` group — is exempt from the mirror/conformance rules.)
  describe ".retired_kind_tokens" do
    it "flags a retired zone-kind token present as a whole word" do
      expect(described_class.retired_kind_tokens(%(kind: "quarantine"))).to eq(["quarantine"])
    end

    it "is clean for live kinds and for the retired token as a substring" do
      expect(described_class.retired_kind_tokens("kind: machine\nkind: canon")).to be_empty
      expect(described_class.retired_kind_tokens("quarantined_entries")).to be_empty
    end
  end

  describe ".retired_manifest_tokens" do
    it "flags a retired manifest-grammar token present as a whole word" do
      expect(described_class.retired_manifest_tokens(%(upkeep: { ttl: 1h }))).to eq(["upkeep"])
      expect(described_class.retired_manifest_tokens(%(on_expire: refresh))).to eq(["on_expire"])
    end

    it "flags ADR 0094 retired render-key tokens as whole words" do
      expect(described_class.retired_manifest_tokens(%(inject_boot: true))).to eq(["inject_boot"])
      expect(described_class.retired_manifest_tokens(%(provenance: false))).to eq(["provenance"])
    end

    it "is clean for live source/retention/publish-target vocabulary and for substrings" do
      expect(described_class.retired_manifest_tokens("source: { from: template }\nretention: {}")).to be_empty
      expect(described_class.retired_manifest_tokens("publish: [{ to: OUT.md, template: t.mustache }]")).to be_empty
      expect(described_class.retired_manifest_tokens("upkeeping_records")).to be_empty
    end
  end

  describe "the live spec tree" do
    let(:spec_root)  { File.expand_path("..", __dir__) }
    let(:spec_files) { Dir.glob(File.join(spec_root, "**", "*_spec.rb")) }

    def dir_segments(path, spec_root)
      rel = Pathname.new(path).relative_path_from(Pathname.new(spec_root))
      dir = rel.dirname.to_s == "." ? [] : rel.dirname.to_s.split("/")
      [rel, dir]
    end

    it "finds the whole moved suite (guard against a silent empty glob)" do
      expect(spec_files.size).to be > 250
    end

    it "has no textus/ duplicate-prefix directory under any category" do
      dupes = SpecLayout::CATEGORIES.select { |c| Dir.exist?(File.join(spec_root, c, "textus")) }
      expect(dupes).to be_empty,
                       "spec/<category>/textus/ duplicates the no-prefix mirror: #{dupes.inspect}"
    end

    it "keeps every spec categorized, mirrored, conformance-stringed, and unit-pure" do
      violations = spec_files.each_with_object([]) do |path, acc|
        rel, dir = dir_segments(path, spec_root)
        category = dir.first
        src = File.read(path)

        unless SpecLayout::CATEGORIES.include?(category)
          acc << "#{rel}: must live under one of #{SpecLayout::CATEGORIES.join("/")}/, not the spec root"
          next
        end

        if SpecLayout.string_described?(src)
          acc << "#{rel}: string-described specs are conformance — move under spec/conformance/" unless category == "conformance"
        elsif (constant = SpecLayout.described_constant(src))
          error = SpecLayout.categorized_placement_error(constant, dir)
          acc << "#{rel}: #{error}" if error
        end

        # The guard's own spec carries the store-backed patterns as test data,
        # so it would trip its own purity check — exempt it explicitly.
        next if File.basename(path) == "spec_layout_spec.rb"

        if category == "unit" && SpecLayout.store_backed?(src)
          acc << "#{rel}: unit specs must be pure — this stands up a Store/tmpdir, so it is integration"
        end
      end

      expect(violations).to be_empty,
                            "Spec layout drifted from the unit/integration/conformance split:\n\n" \
                            "#{violations.join("\n")}"
    end

    # ADR 0092: a zone-kind token a sweep retired must not creep back into a spec
    # body — only the dedicated kind-guards (which assert its rejection) may name
    # it, so a straggler after a rename fails CI instead of lingering as noise.
    it "lets no retired zone-kind token leak outside the kind-guards" do
      offenders = spec_files.each_with_object([]) do |path, acc|
        next if SpecLayout::RETIRED_TOKEN_GUARDS.include?(File.basename(path))

        dead = SpecLayout.retired_kind_tokens(File.read(path))
        acc << "#{dir_segments(path, spec_root).first}: #{dead.inspect}" if dead.any?
      end

      expect(offenders).to be_empty,
                           "Retired zone-kind tokens (ADR 0092) — use the fixture vocabulary " \
                           "in spec/support/:\n\n#{offenders.join("\n")}"
    end

    # ADR 0093: the retired manifest grammar (upkeep / on_change / source_change /
    # on_expire) must not creep back into a spec body — only the guards that
    # assert its rejection may name it. Production now lives in `source:` and
    # age-GC in the `retention:` rule.
    it "lets no retired manifest-grammar token leak outside the rejection guards" do
      offenders = spec_files.each_with_object([]) do |path, acc|
        next if SpecLayout::RETIRED_MANIFEST_TOKEN_GUARDS.include?(File.basename(path))

        dead = SpecLayout.retired_manifest_tokens(File.read(path))
        acc << "#{dir_segments(path, spec_root).first}: #{dead.inspect}" if dead.any?
      end

      expect(offenders).to be_empty,
                           "Retired manifest tokens (ADR 0093) — use source:/retention: " \
                           "vocabulary:\n\n#{offenders.join("\n")}"
    end
  end
end
