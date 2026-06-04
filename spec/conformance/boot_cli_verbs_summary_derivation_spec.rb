require "spec_helper"

# Guard (ADR 0039): a verb's summary is a fact derived from its contract, not
# editorial presentation. Where a boot catalog verb has a Dispatcher contract,
# its surfaced summary must equal that contract's — and the curated source must
# not carry a second hand-typed copy that could silently drift.
RSpec.describe "Boot::CLI_VERBS summaries derive from contracts (ADR 0039)" do
  let(:by_name) { Textus::Boot.contract_summaries }

  it "matches the contract summary for every catalog verb that has one" do
    drift = Textus::Boot::CLI_VERBS.filter_map do |v|
      want = by_name[v["name"]]
      next if want.nil? || want == v["summary"]

      "#{v["name"]}: catalog=#{v["summary"].inspect} contract=#{want.inspect}"
    end
    expect(drift).to be_empty, "CLI_VERBS summary drift:\n#{drift.join("\n")}"
  end

  it "carries no literal summary in the curated source for a verb that has a contract" do
    redundant = Textus::Boot::CURATED_CLI_VERBS.filter_map do |v|
      "#{v["name"]}: #{v["summary"].inspect}" if by_name.key?(v["name"]) && v.key?("summary")
    end
    expect(redundant).to be_empty,
                         "These curated verbs hand-type a summary their contract already owns:\n#{redundant.join("\n")}"
  end
end
