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

  # The post-Phase-1 rule: a category segment (unit/integration/conformance)
  # wraps the existing lib/-mirror. Written ahead of the file move; the live
  # sweep below still uses the flat `.placement_error` until the move lands.
  describe ".categorized_placement_error" do
    it "passes a unit spec mirrored below its category" do
      expect(described_class.categorized_placement_error("Textus::Ports::BuildLock", %w[unit ports])).to be_nil
    end

    it "passes an integration spec mirrored below its category" do
      expect(described_class.categorized_placement_error("Textus::Read::Get", %w[integration read])).to be_nil
    end

    it "flags a spec sitting at the spec root (no category)" do
      expect(described_class.categorized_placement_error("Textus::Read::Get", [])).not_to be_nil
    end

    it "flags an unknown leading segment that is not a category" do
      err = described_class.categorized_placement_error("Textus::Read::Get", %w[read])
      expect(err).to match(/not a category/)
    end

    it "flags a misfiled spec under the wrong mirror dir within a category" do
      expect(described_class.categorized_placement_error("Textus::Ports::BuildLock", %w[unit read])).not_to be_nil
    end
  end

  # The live guard: no resurrected spec/textus/ prefix dir, and every
  # constant-described spec sits in its mirror directory.
  describe "the live spec tree" do
    let(:spec_root) { __dir__ }
    let(:spec_files) { Dir.glob(File.join(spec_root, "**", "*_spec.rb")) }

    it "finds spec files (guard against a silent empty glob)" do
      expect(spec_files).not_to be_empty
    end

    it "has no spec/textus/ duplicate-prefix directory" do
      expect(Dir.exist?(File.join(spec_root, "textus"))).to(
        be(false),
        "spec/textus/ is a duplicate of the no-prefix mirror; specs for " \
        "Textus::Foo belong in spec/foo/, not spec/textus/foo/",
      )
    end

    it "places every constant-described spec in its mirror directory" do
      violations = spec_files.each_with_object([]) do |path, acc|
        constant = SpecLayout.described_constant(File.read(path))
        next unless constant # string-described (integration) specs are exempt

        rel = Pathname.new(path).relative_path_from(Pathname.new(spec_root))
        dir = rel.dirname.to_s == "." ? [] : rel.dirname.to_s.split("/")

        error = SpecLayout.placement_error(constant, dir)
        acc << "#{rel}: #{error}" if error
      end

      expect(violations).to be_empty,
                            "Spec layout drifted from the lib/textus/ mirror:\n\n" \
                            "#{violations.join("\n")}"
    end
  end
end
