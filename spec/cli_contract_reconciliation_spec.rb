require "spec_helper"

# ADR 0063: the CLI is a projection of the contract. Every :cli contract must
# resolve to a registered command at its declared path, and every projected /
# escape-hatch command must dispatch the verb its own contract names — so a CLI
# command can never silently dispatch a differently-named verb.

# Verbs whose CLI command path cannot resolve via standard command_name/
# parent_group discovery (documented exceptions only). Populate ONLY if needed.
#
# Current state: no exemptions required. Group::Fetch carries command_name
# "fetch" and appears in Verb.descendants, satisfying the :fetch cli_path.
# Verb::FetchAll has command_name "all" + parent_group Group::Fetch, giving
# path "fetch all" — also fully discoverable. Verb::Fetch itself has no
# command_name and is therefore invisible to the second check by design.
CLI_RECONCILE_EXEMPT = %i[].freeze

Textus::CLI.verbs # trigger Runner.install! so Gen* exist

RSpec.describe "CLI reconciles with the contract (ADR 0063)" do
  def cli_specs
    Textus::Dispatcher::VERBS.values
                             .select { |k| k.respond_to?(:contract?) && k.contract? && k.contract.cli? }
                             .map(&:contract)
                             .reject { |s| CLI_RECONCILE_EXEMPT.include?(s.verb) }
  end

  def path_of(klass)
    grp = klass.parent_group
    grp ? "#{grp.command_name} #{klass.command_name}" : klass.command_name
  end

  def registered_paths
    Textus::CLI::Verb.descendants.select(&:command_name).map { |k| path_of(k) }
  end

  it "every :cli contract has a registered command at its declared path" do
    missing = cli_specs.reject { |s| registered_paths.include?(s.cli_path) }
    message = "no command registered at the cli_path for: " \
              "#{missing.map { |s| "#{s.verb} -> '#{s.cli_path}'" }.join(", ")}"
    expect(missing.map(&:verb)).to be_empty, message
  end

  it "every contract-projected/escape-hatch command dispatches the verb its own contract names" do
    offenders = Textus::CLI::Verb.descendants.select do |k|
      k.command_name && k.respond_to?(:spec) && k.spec
    end.reject do |k|
      # The command sits at its own contract's declared cli_path, and its
      # contract verb is a real dispatcher verb.
      path_of(k) == k.spec.cli_path && Textus::Dispatcher::VERBS.key?(k.spec.verb)
    end
    expect(offenders.map { |k| [k.name, path_of(k), k.spec.verb] }).to be_empty
  end

  it "every invokable Runner::Base command declares its contract via self.spec" do
    # A Runner::Base subclass derives its name/dispatch from `spec`; one that
    # forgot `self.spec = …` would silently escape the dispatch check above.
    # Fail loudly instead — drift must be unrepresentable, not merely unchecked.
    nil_spec = Textus::CLI::Verb.descendants.select do |k|
      k.command_name && k < Textus::CLI::Runner::Base && k.spec.nil?
    end
    expect(nil_spec.map(&:name)).to be_empty,
                                    "Runner::Base commands missing self.spec: #{nil_spec.map(&:name).join(", ")}"
  end
end
