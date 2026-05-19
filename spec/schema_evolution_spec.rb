require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Schema evolution metadata" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "schemas/person.yaml"), <<~YAML)
      name: person
      required: [full_name]
      fields:
        full_name:  { type: string, maintained_by: human }
        embedding:  { type: array,  maintained_by: ai }
        last_seen:  { type: time,   maintained_by: script }
      evolution:
        added_in: 2026-05-19
        migrate_from:
          name: full_name
    YAML
  end
  after { FileUtils.remove_entry(tmp) }

  it "exposes maintained_by per field" do
    s = Textus::Schema.load(File.join(root, "schemas/person.yaml"))
    expect(s.maintained_by("full_name")).to eq("human")
    expect(s.maintained_by("embedding")).to eq("ai")
    expect(s.maintained_by("missing")).to be_nil
  end

  it "exposes evolution metadata" do
    s = Textus::Schema.load(File.join(root, "schemas/person.yaml"))
    expect(s.evolution["added_in"]).to eq("2026-05-19")
    expect(s.evolution["migrate_from"]).to eq({ "name" => "full_name" })
  end
end
