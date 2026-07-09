RSpec.describe Textus::Protocol::Builder::Runtime do # rubocop:disable RSpec/MultipleMemoizedHelpers
  let(:layout) { instance_double(Textus::Protocol::Layout) }
  let(:database) { instance_double(Textus::Infra::Database) }
  let(:file_system) { instance_double(Textus::Infra::FileSystem) }
  let(:store) { instance_double(Textus::Infra::Store) }
  let(:infra) do
    instance_double(Textus::Protocol::Builder::Infrastructure::Components,
                    database: database, file_system: file_system, store: store, layout: layout)
  end
  let(:manifest) { instance_double(Textus::Protocol::Manifest) }
  let(:resolver) { instance_double(Textus::Protocol::Manifest::Resolver) }
  let(:schemas) { instance_double(Textus::Protocol::Schema::Registry) }
  let(:workflows) { [] }
  let(:workflow_registry) { instance_double(Textus::Workflow::Registry) }
  let(:domain) do
    instance_double(Textus::Protocol::Builder::Domain::Components,
                    manifest: manifest, schemas: schemas,
                    workflows: workflows, workflow_registry: workflow_registry)
  end

  before do
    allow(manifest).to receive_messages(resolver: resolver, policy: double)
    allow(store).to receive(:workflow_queue).and_return(double)
    allow(layout).to receive(:root).and_return("/tmp/test")
    allow(file_system).to receive(:respond_to?).with(:exists?).and_return(true)
    allow(file_system).to receive(:respond_to?).with(:mtime).and_return(true)
    allow(file_system).to receive(:respond_to?).with(:read).and_return(true)

    db_double = instance_double(Sequel::Database)
    allow(database).to receive(:connection).and_return(db_double)
    allow(db_double).to receive(:[]).with(:sessions).and_return(double("dataset", insert: nil,
      where: double("where", first: nil, update: nil, delete: 0)))
  end

  it "builds a StoreEngine" do
    result = subject.call(infra: infra, domain: domain, root: "/tmp/test")
    expect(result.store_engine).to be_a(Textus::Protocol::StoreEngine)
  end

  it "builds a Gate wired to the StoreEngine" do
    result = subject.call(infra: infra, domain: domain, root: "/tmp/test")
    expect(result.gate).to be_a(Textus::Protocol::Gate)
  end

  it "builds a Container with all components" do
    result = subject.call(infra: infra, domain: domain, root: "/tmp/test")
    expect(result.container).to be_a(Textus::Protocol::Container)
    expect(result.container.store).to eq(store)
    expect(result.container.layout).to eq(layout)
    expect(result.container.manifest).to eq(manifest)
    expect(result.container.schemas).to eq(schemas)
  end

  it "wires store_engine on the Container" do
    result = subject.call(infra: infra, domain: domain, root: "/tmp/test")
    store_engine = result.store_engine
    expect(store_engine).to respond_to(:read)
    expect(store_engine).to respond_to(:put)
  end
end
