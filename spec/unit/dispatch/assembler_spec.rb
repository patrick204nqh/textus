require "spec_helper"

RSpec.describe Textus::Dispatch::Assembler do
  describe "HANDLER_MANIFEST" do
    it "covers every registered verb contract" do
      expected_contracts = Textus::VerbRegistry.registered
                                               .filter_map { |s| Textus::VerbRegistry.contract_class_for(s.verb) }
                                               .to_set
      manifest_contracts = described_class::HANDLER_MANIFEST.to_set(&:first)
      missing = expected_contracts - manifest_contracts
      extra   = manifest_contracts - expected_contracts
      expect(missing).to be_empty,
                         "verb contracts missing from HANDLER_MANIFEST: #{missing.map(&:name)}"
      expect(extra).to be_empty,
                       "HANDLER_MANIFEST entries absent from VerbRegistry: #{extra.map(&:name)}"
    end

    it "each row is [contract_class, handler_class, Hash]" do
      described_class::HANDLER_MANIFEST.each do |row|
        expect(row.size).to eq(3), "row for #{row.first} has #{row.size} elements"
        expect(row[0]).to be_a(Class)
        expect(row[1]).to be_a(Module)
        expect(row[2]).to be_a(Hash)
      end
    end

    it "all dep_map values are Symbols in COMPUTED_KEYS" do
      described_class::HANDLER_MANIFEST.each do |_contract, _handler, dep_map|
        dep_map.each_value do |v|
          expect(described_class::COMPUTED_KEYS).to include(v),
                                                    "dep_map value :#{v} is not in COMPUTED_KEYS"
        end
      end
    end
  end
end
