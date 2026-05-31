require "spec_helper"

# Guard (ADR 0039): where a boot catalog verb has a Dispatcher contract, its
# summary is DERIVED from that contract — not a second hand-typed copy.
RSpec.describe "Boot::CLI_VERBS summaries derive from contracts (ADR 0039)" do
  it "matches the contract summary for every catalog verb that has one" do
    by_name = Textus::Dispatcher::VERBS.values
                                       .select { |k| k.respond_to?(:contract?) && k.contract? }
                                       .to_h { |k| [k.contract.verb.to_s, k.contract.summary] }

    drift = Textus::Boot::CLI_VERBS.filter_map do |v|
      want = by_name[v["name"]]
      next if want.nil? || want == v["summary"]

      "#{v["name"]}: catalog=#{v["summary"].inspect} contract=#{want.inspect}"
    end
    expect(drift).to be_empty, "CLI_VERBS summary drift:\n#{drift.join("\n")}"
  end
end
