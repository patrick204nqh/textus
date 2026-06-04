require "spec_helper"

RSpec.describe "Textus::Etag.for_contract" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "hooks"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), "version: textus/3\n")
    File.write(File.join(root, "hooks/a.rb"), "Textus.hook { |reg| }\n")
    File.write(File.join(root, "schemas/x.yaml"), "type: object\n")
  end

  after { FileUtils.remove_entry(tmp) }

  def etag = Textus::Etag.for_contract(root)

  it "produces a stable sha256-prefixed digest" do
    expect(etag).to start_with("sha256:")
    expect(etag).to eq(Textus::Etag.for_contract(root))
  end

  it "changes when the manifest changes" do
    was = etag
    File.write(File.join(root, "manifest.yaml"), "version: textus/3\n# edit\n")
    expect(etag).not_to eq(was)
  end

  it "changes when a hook file changes" do
    was = etag
    File.write(File.join(root, "hooks/a.rb"), "Textus.hook { |reg| } # edit\n")
    expect(etag).not_to eq(was)
  end

  it "changes when a schema file changes" do
    was = etag
    File.write(File.join(root, "schemas/x.yaml"), "type: string\n")
    expect(etag).not_to eq(was)
  end

  it "changes when a new hook file is added" do
    was = etag
    File.write(File.join(root, "hooks/b.rb"), "Textus.hook { |reg| }\n")
    expect(etag).not_to eq(was)
  end
end
