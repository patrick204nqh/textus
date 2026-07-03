RSpec.describe Textus::Lanes::Ingest::IndexRebuilder do
  describe ".rebuild!" do
    it "delegates to Index::Builder" do
      event_store = instance_double("EventStore")
      resolver = instance_double("Resolver")
      builder = instance_double("Index::Builder")
      allow(Textus::Infra::Store::Index::Builder).to receive(:new).with(store: event_store).and_return(builder)
      expect(builder).to receive(:rebuild!).with(resolver:)

      described_class.rebuild!(event_store, resolver)
    end
  end
end
