# frozen_string_literal: true

# Unit examples for the pure SpecLayout helper. The directory sweep that uses
# it lives in the second describe block (added in Task 2).
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
end
