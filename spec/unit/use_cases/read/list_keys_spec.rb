require "spec_helper"

RSpec.describe Textus::UseCases::Read::ListKeys do
  subject(:use_case) { described_class.new }

  let(:manifest) { instance_double(Textus::Protocol::Manifest) }
  let(:file_system) { instance_double(Textus::Infra::FileStore) }
  let(:layout) { instance_double(Textus::Protocol::Layout) }
  let(:entry_index) { instance_double(Textus::Protocol::Index) }
  let(:command) { instance_double(Textus::Dispatch::Contracts::ListKeys, q: "hello", schema: nil, lane: nil, prefix: nil) }

  before do
    use_case.instance_variable_set(:@command, command)
    use_case.instance_variable_set(:@manifest, manifest)
    use_case.instance_variable_set(:@file_system, file_system)
    use_case.instance_variable_set(:@layout, layout)
    use_case.instance_variable_set(:@entry_index, entry_index)
  end

  describe "#call" do
    it "delegates to entry_index.search when q or schema is present" do
      allow(entry_index).to receive(:search).with(query: "hello", schema: nil, lane: nil, prefix: nil)
                                            .and_return([{ "key" => "knowledge.a", "lane" => "knowledge" }])

      result = use_case.call

      expect(result).to be_success
      expect(result.value).to eq([{ "key" => "knowledge.a", "lane" => "knowledge" }])
    end
  end
end
