# spec/integration/step/store_wiring_spec.rb
require "spec_helper"

RSpec.describe Textus::Store do
  describe "step wiring" do
    def init_store(root)
      Textus::Init.run(File.join(root, ".textus"))
      Textus::Store.new(File.join(root, ".textus"))
    end

    it "exposes container.steps as a Step::RegistryStore" do
      Dir.mktmpdir do |root|
        store = init_store(root)
        expect(store.steps).to be_a(Textus::Step::RegistryStore)
      end
    end

    it "registers built-in fetch steps and discovered steps" do
      Dir.mktmpdir do |root|
        store = init_store(root)
        expect(store.steps.names(:fetch)).to include(:json)
      end
    end

    it "no longer exposes events or rpc" do
      Dir.mktmpdir do |root|
        store = init_store(root)
        expect(store).not_to respond_to(:rpc)
        expect(store.container.members).to include(:steps)
        expect(store.container.members).not_to include(:events, :rpc)
      end
    end
  end
end
