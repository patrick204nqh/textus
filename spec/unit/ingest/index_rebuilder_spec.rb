RSpec.describe Textus::Lanes::Ingest::IndexRebuilder do
  describe ".rebuild!" do
    it "delegates to Index::Builder" do
      db = instance_double("Database")
      resolver = instance_double("Resolver")
      builder = instance_double("Index::Builder")
      allow(Textus::Infra::Store::Index::Builder).to receive(:new).with(db).and_return(builder)
      expect(builder).to receive(:rebuild!).with(resolver:)

      described_class.rebuild!(db, resolver)
    end
  end
end
