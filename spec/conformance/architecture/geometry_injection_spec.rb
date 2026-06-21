RSpec.describe "Envelope path resolution" do
  it "Writer delegates zone paths to Geometry" do
    writer = Textus::Store::Envelope::Writer
    expect(writer.instance_method(:initialize).parameters).to include(%i[keyreq geometry])
  end

  it "Reader delegates zone paths to Geometry" do
    reader = Textus::Store::Envelope::Reader
    expect(reader.instance_method(:initialize).parameters).to include(%i[keyreq geometry])
  end
end
