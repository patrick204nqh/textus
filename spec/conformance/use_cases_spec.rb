# frozen_string_literal: true

# Guard spec: enforces ADR-0125 bounded use-case invariants.
#
# Each use-case module must:
#   1. Define HANDLES (singular, NOT HANDLES_ALL) — one contract per module
#   2. Define NEEDS listing only valid Infrastructure keys
#   3. Implement .call(command, call, deps) returning Value::Result

USE_CASE_GLOB = File.expand_path("../../lib/textus/use_cases/**/*.rb", __dir__)

# Valid keys from Store::Infrastructure.members
VALID_NEEDS_KEYS = %i[
  manifest file_store schemas audit_log job_store layout
  link_edge_store workflows event_bus freshness_evaluator
  trace_buffer pipeline
].freeze

RSpec.describe "Use-case module invariants (ADR-0125)" do
  let(:use_case_modules) do
    # Scan namespace constants like HandlerResolver.discover_all does
    [Textus::UseCases::Read, Textus::UseCases::Write, Textus::UseCases::Ops].flat_map do |ns|
      ns.constants(false).filter_map { |c| ns.const_get(c) }.grep(Module)
    end
  end

  it "finds at least one use-case module" do
    expect(use_case_modules).not_to be_empty
  end

  it "each module defines HANDLES (singular, not plural)" do
    use_case_modules.each do |mod|
      expect(mod.const_defined?(:HANDLES)).to be(true),
                                              "#{mod.name} missing HANDLES constant"
      expect(mod.const_defined?(:HANDLES_ALL)).to be(false),
                                                  "#{mod.name} defines HANDLES_ALL instead of HANDLES (one contract per module)"
    end
  end

  it "each module defines NEEDS with valid Infrastructure keys" do
    use_case_modules.each do |mod|
      expect(mod.const_defined?(:NEEDS)).to be(true),
                                            "#{mod.name} missing NEEDS constant"
      needs = mod::NEEDS
      expect(needs).to be_an(Array)
      needs.each do |key|
        expect(VALID_NEEDS_KEYS).to include(key),
                                    "#{mod.name} lists :#{key} in NEEDS but it is not a valid Infrastructure key"
      end
    end
  end

  it "each module responds to .call(command, call, deps)" do
    use_case_modules.each do |mod|
      expect(mod.respond_to?(:call)).to be(true),
                                        "#{mod.name} does not implement .call"
      arity = mod.method(:call).arity
      expect([2, 3]).to include(arity),
                        "#{mod.name}.call has arity #{arity}, expected 2 or 3 (command, call, deps)"
    end
  end

  it "no module defines HANDLES_ALL (removed — use HANDLES only)" do
    offenders = use_case_modules.select { |m| m.const_defined?(:HANDLES_ALL) }
    expect(offenders).to be_empty,
                          "#{offenders.map(&:name).join(', ')} define HANDLES_ALL — only HANDLES (singular) is supported"
  end
end
