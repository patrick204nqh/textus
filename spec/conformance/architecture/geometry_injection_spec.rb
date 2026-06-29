RSpec.describe "Envelope path resolution" do
  it "Writer delegates zone paths to Geometry" do
    writer = Textus::Store::Entry::Writer
    expect(writer.instance_method(:initialize).parameters).to include(%i[keyreq layout])
  end

  it "Reader delegates zone paths to Geometry" do
    reader = Textus::Store::Entry::Reader
    expect(reader.instance_method(:initialize).parameters).to include(%i[keyreq layout])
  end
end
