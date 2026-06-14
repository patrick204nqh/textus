RSpec.describe "project .textus manifest -- live fixture contract" do
  let(:project_textus) { File.expand_path("../../../.textus", __dir__) }
  let(:store) { Textus::Store.new(project_textus) }

  it "loads without raising" do
    expect { store.manifest }.not_to raise_error
  end

  it "declares the textus/3 protocol version" do
    expect(store.manifest.data.raw["version"]).to eq("textus/3")
  end

  it "has at least one entry" do
    expect(store.manifest.data.entries).not_to be_empty
  end

  it "resolves every declared entry to a concrete path without raising" do
    store.manifest.data.entries.each do |entry|
      expect { store.manifest.resolver.resolve(entry.key) }.not_to raise_error,
                                                                   "failed to resolve entry #{entry.key.inspect}"
    end
  end
end
