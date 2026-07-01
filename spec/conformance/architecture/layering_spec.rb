require "spec_helper"

# ADR 0106 — the hexagonal layering (surfaces -> use cases -> domain -> ports
# -> adapters) is real but was implicit: `ls` cannot see it and nothing enforced
# it. This makes the load-bearing rule executable — the pure domain layer must
# not reach UP into the use-case or surface layers. Everything flows inward to
# the domain; the domain depends on nothing above it.

# The layers above the domain. A domain file naming any of these is reaching up
# out of the pure core. A local (not a constant) to avoid leaking into specs.
layers_above_domain = %w[Read Write Maintenance Produce CLI MCP]

RSpec.describe "layering invariant (ADR 0106)" do
  def domain_files
    Dir[File.expand_path("../../../lib/textus/domain/**/*.rb", __dir__)]
  end

  it "has domain files to check (guard is wired to a real tree)" do
    expect(domain_files).not_to be_empty, "domain/ is empty — run Phase 2 of the architecture deepening"
  end

  layers_above_domain.each do |layer|
    it "domain/ never references Textus::#{layer}::" do
      offenders = domain_files.select { |f| File.read(f).match?(/\bTextus::#{layer}::/) }
      expect(offenders).to be_empty,
                           "lib/textus/domain reaches up into Textus::#{layer}:: in:\n  " \
                           "#{offenders.map { |f| f.sub(%r{.*/lib/}, "lib/") }.join("\n  ")}\n" \
                           "Domain is the pure core (ADR 0106) — invert the dependency or move " \
                           "the logic into the use-case layer that owns it."
    end
  end
end
