require "spec_helper"

Textus::Surfaces::CLI.verbs # trigger Runner.install! so Gen* exist

# Verbs whose #call signature is intentionally a superset of the wire args
# (extra params with no MCP exposure). Keep empty unless justified.
# `key_delete` carries an internal-only `suppress_events:` kwarg — the proposal
# reject path deletes the pending entry silently (`write/reject.rb`), so the
# event is suppressed there but the flag is never a wire arg (ADR 0060 amendment;
# verb renamed from `delete` in ADR 0082).
# `audit` uses **filters (keyrest) in #call, so declared arg names cannot match
# the single :filters param name — the contract expresses the meaningful filter
# kwargs that Query.build accepts (ADR 0063).
CONTRACT_SIGNATURE_EXEMPT = %i[key_delete audit].freeze

RSpec.describe "contract reconciliation" do
  def verb_signature_for(klass)
    if klass <= Textus::Action::Base
      klass.instance_method(:initialize).parameters
    else
      klass.instance_method(:call).parameters
    end
  end

  def positional_param_kind?(klass, kind)
    if klass <= Textus::Action::Base
      kind == :keyreq
    else
      %i[req opt].include?(kind)
    end
  end

  # Guard (ADR 0039): a verb's declared `arg` names must match its use-case
  # #call parameters exactly. This is the link that makes the derived MCP schema
  # honest — rename a kwarg and forget the contract, and this fails.
  describe "args reconcile with use-case #call (ADR 0039)" do
    Textus::Action::VERBS.each do |verb, klass|
      next unless klass.respond_to?(:contract?) && klass.contract?

      it "#{verb}: dispatcher key matches the contract's own verb" do
        expect(klass.contract.verb).to eq(verb),
                                       "Dispatcher registers #{klass} under :#{verb} " \
                                       "but its contract declares verb :#{klass.contract.verb}"
      end

      it "#{verb}: declared args == #call parameters" do
        params = verb_signature_for(klass)
        call_names = params.map { |_kind, name| name }.compact.sort
        declared   = klass.contract.args.map(&:name).sort
        next if CONTRACT_SIGNATURE_EXEMPT.include?(verb)

        expect(declared).to eq(call_names),
                            "#{verb}: contract args #{declared.inspect} != #call params #{call_names.inspect}"
      end

      it "#{verb}: positional contract args are positional in #call" do
        params = verb_signature_for(klass).to_h { |kind, name| [name, kind] }
        klass.contract.args.each do |a|
          expected_positional = if klass <= Textus::Action::Base
                                  a.positional ? %i[keyreq key].include?(params[a.name]) : a.positional
                                else
                                  positional_param_kind?(klass, params[a.name])
                                end
          expect(a.positional).to eq(expected_positional),
                                  "#{verb}: arg #{a.name} positional=#{a.positional} but #call has it as #{params[a.name]}"
        end
      end
    end
  end

  # Guard (ADR 0068): the declarative facets that replaced escape-hatch classes
  # must stay resolvable. Every around: names a registered resource; every
  # cli_stdin mode is supported; every default view tolerates the uniform
  # (result, inputs) call. Drift becomes a red test, not a runtime surprise.
  describe "facets (ADR 0068)" do
    let(:specs) do
      Textus::Action::VERBS.values
                           .select { |k| k.respond_to?(:contract?) && k.contract? }
                           .map(&:contract)
    end

    it "every around: names a registered resource" do
      specs.select(&:around).each do |s|
        expect { Textus::Dispatch::Around.fetch(s.around) }
          .not_to(raise_error, "verb #{s.verb} around #{s.around.inspect}")
      end
    end

    it "every cli_stdin mode is supported" do
      expect(specs.filter_map(&:cli_stdin).uniq).to all(eq(:json))
    end

    it "every default view is callable with (result, inputs)" do
      specs.each do |s|
        expect(s.view(:default)).to respond_to(:call)
        # arity tolerance: a one-param view must accept the second arg
        expect(s.view(:default).arity).to be <= 2
      end
    end
  end

  # ADR 0063: the CLI is a projection of the contract. Every :cli contract must
  # resolve to a registered command at its declared path, and every projected /
  # escape-hatch command must dispatch the verb its own contract names — so a CLI
  # command can never silently dispatch a differently-named verb.
  describe "CLI reconciles with the contract (ADR 0063)" do
    let(:cli_specs) do
      Textus::Action::VERBS.values
                           .select { |k| k.respond_to?(:contract?) && k.contract? && k.contract.cli? }
                           .map(&:contract)
    end

    def path_of(klass)
      grp = klass.parent_group
      grp ? "#{grp.command_name} #{klass.command_name}" : klass.command_name
    end

    def registered_paths
      Textus::Surfaces::CLI::Verb.descendants.select(&:command_name).map { |k| path_of(k) }
    end

    it "every :cli contract has a registered command at its declared path" do
      missing = cli_specs.reject { |s| registered_paths.include?(s.cli_path) }
      message = "no command registered at the cli_path for: " \
                "#{missing.map { |s| "#{s.verb} -> '#{s.cli_path}'" }.join(", ")}"
      expect(missing.map(&:verb)).to be_empty, message
    end

    it "every contract-projected/escape-hatch command dispatches the verb its own contract names" do
      offenders = Textus::Surfaces::CLI::Verb.descendants.select do |k|
        # Anonymous (name.nil?) subclasses are throwaway fixtures other specs
        # build with Class.new(Verb); they leak into .descendants and would
        # offend this seed-sensitively. Real commands are always named constants.
        k.name && k.command_name && k.respond_to?(:spec) && k.spec
      end.reject do |k|
        # The command sits at its own contract's declared cli_path, and its
        # contract verb is a real dispatcher verb.
        path_of(k) == k.spec.cli_path && Textus::Action::VERBS.key?(k.spec.verb)
      end
      expect(offenders.map { |k| [k.name, path_of(k), k.spec.verb] }).to be_empty
    end

    it "every invokable Runner::Base command declares its contract via self.spec" do
      # A Runner::Base subclass derives its name/dispatch from `spec`; one that
      # forgot `self.spec = …` would silently escape the dispatch check above.
      # Fail loudly instead — drift must be unrepresentable, not merely unchecked.
      nil_spec = Textus::Surfaces::CLI::Verb.descendants.select do |k|
        k.command_name && k < Textus::Surfaces::CLI::Runner::Base && k.spec.nil?
      end
      expect(nil_spec.map(&:name)).to be_empty,
                                      "Runner::Base commands missing self.spec: #{nil_spec.map(&:name).join(", ")}"
    end
  end
end
