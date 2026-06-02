require "spec_helper"

# Guard (ADR 0039): a verb's declared `arg` names must match its use-case
# #call parameters exactly. This is the link that makes the derived MCP schema
# honest — rename a kwarg and forget the contract, and this fails.

# Verbs whose #call signature is intentionally a superset of the wire args
# (extra params with no MCP exposure). Keep empty unless justified.
# `delete` carries an internal-only `suppress_events:` kwarg — the proposal
# reject path deletes the pending entry silently (`write/reject.rb`), so the
# event is suppressed there but the flag is never a wire arg (ADR 0060 amendment).
CONTRACT_SIGNATURE_EXEMPT = %i[delete].freeze

RSpec.describe "Contract args reconcile with use-case #call (ADR 0039)" do
  Textus::Dispatcher::VERBS.each do |verb, klass|
    next unless klass.respond_to?(:contract?) && klass.contract?

    it "#{verb}: declared args == #call parameters" do
      params = klass.instance_method(:call).parameters
      call_names = params.map { |_kind, name| name }.compact.sort
      declared   = klass.contract.args.map(&:name).sort
      next if CONTRACT_SIGNATURE_EXEMPT.include?(verb)

      expect(declared).to eq(call_names),
                          "#{verb}: contract args #{declared.inspect} != #call params #{call_names.inspect}"
    end

    it "#{verb}: positional contract args are positional in #call" do
      params = klass.instance_method(:call).parameters.to_h { |kind, name| [name, kind] }
      klass.contract.args.each do |a|
        expected_positional = %i[req opt].include?(params[a.name])
        expect(a.positional).to eq(expected_positional),
                                "#{verb}: arg #{a.name} positional=#{a.positional} but #call has it as #{params[a.name]}"
      end
    end
  end
end
