require "spec_helper"

RSpec.describe "Textus per-event sugar" do
  let(:reg) { Textus::Hooks::Registry.new }

  around { |ex| Textus.with_registry(reg) { ex.run } }

  describe ".fetch" do
    it "registers a fetch hook by name" do
      Textus.fetch(:local_file) do |config:, args:, **|
        [config, args]
        { _meta: {}, body: "ok" }
      end
      out = reg.rpc_callable(:fetch, :local_file).call(store: nil, config: {}, args: {})
      expect(out[:body]).to eq("ok")
    end

    it "accepts a string name and normalizes to a symbol" do
      Textus.fetch("from_string") do |config:, args:, **|
        [config, args]
        { _meta: {}, body: "s" }
      end
      expect(reg.rpc_names(:fetch)).to include(:from_string)
    end

    it "raises outside with_registry" do
      Thread.new do
        expect do
          Textus.fetch(:naked) { |config:, args:, **| [config, args] }
        end.to raise_error(Textus::UsageError, /no active registry/)
      end.join
    end
  end
end
