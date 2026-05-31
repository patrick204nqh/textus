require "spec_helper"

# Guard (ADR 0037): the agent protocol template embeds prose refs like
# "SPEC.md §8" / "§5". When SPEC is renumbered, those rot silently and agents
# get pointed at the wrong section. Assert every referenced section heading
# still exists.

BOOT_RB = File.expand_path("../lib/textus/boot.rb", __dir__)
SPEC_MD = File.expand_path("../SPEC.md", __dir__)

RSpec.describe "boot.rb SPEC section refs resolve to real headings (ADR 0037)" do
  let(:referenced_sections) do
    File.read(BOOT_RB).scan(/SPEC\.md\s+§(\d+)/).flatten.uniq.sort_by(&:to_i)
  end
  let(:spec_headings) do
    File.readlines(SPEC_MD).filter_map { |l| l[/^##\s+(\d+)\./, 1] }
  end

  it "finds at least one SPEC ref (guard against a silent empty scan)" do
    expect(referenced_sections).not_to be_empty
  end

  it "every referenced §N has a matching '## N.' heading in SPEC.md" do
    missing = referenced_sections - spec_headings
    expect(missing).to be_empty,
                       "boot.rb references SPEC sections with no heading: " \
                       "#{missing.map { |n| "§#{n}" }.inspect}"
  end
end
