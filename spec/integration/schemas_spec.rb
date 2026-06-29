require "spec_helper"

RSpec.describe Textus::Schema::Registry do
  let(:tmp) { Dir.mktmpdir("textus-schemas") }
  let(:agent_yaml) do
    <<~YAML
      name: agent
      required: [name]
      fields:
        name: { type: string }
    YAML
  end
  let(:skill_yaml) do
    <<~YAML
      name: skill
      required: [name]
      fields:
        name: { type: string }
    YAML
  end

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  def write_schema(dir, name, body)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{name}.yaml"), body)
  end

  describe "construction" do
    it "eagerly loads every *.yaml under the directory" do
      write_schema(tmp, "agent", agent_yaml)
      write_schema(tmp, "skill", skill_yaml)
      schemas = described_class.new(tmp)
      expect(schemas.all.size).to eq(2)
      expect(schemas.all).to all(be_a(Textus::Schema))
    end

    it "does not raise when the directory does not exist" do
      missing = File.join(tmp, "nope")
      expect { described_class.new(missing) }.not_to raise_error
      expect(described_class.new(missing).all).to eq([])
    end
  end

  describe "#fetch" do
    it "returns a Schema for a known name" do
      write_schema(tmp, "agent", agent_yaml)
      schemas = described_class.new(tmp)
      expect(schemas.fetch("agent")).to be_a(Textus::Schema)
      expect(schemas.fetch("agent").name).to eq("agent")
    end

    it "raises IoError with the expected schema path in the message when missing" do
      schemas = described_class.new(tmp)
      expected_path = File.join(tmp, "missing.yaml")
      expect { schemas.fetch("missing") }.to raise_error(Textus::IoError, "schema not found: #{expected_path}")
    end
  end

  describe "#fetch_or_nil" do
    it "returns nil when name is nil" do
      schemas = described_class.new(tmp)
      expect(schemas.fetch_or_nil(nil)).to be_nil
    end

    it "returns the Schema when known" do
      write_schema(tmp, "agent", agent_yaml)
      schemas = described_class.new(tmp)
      expect(schemas.fetch_or_nil("agent")).to be_a(Textus::Schema)
    end

    it "raises IoError when the named schema is missing (only nil short-circuits)" do
      schemas = described_class.new(tmp)
      expect { schemas.fetch_or_nil("missing") }.to raise_error(Textus::IoError, /schema not found:/)
    end
  end

  describe "#all" do
    it "enumerates the loaded schemas" do
      write_schema(tmp, "agent", agent_yaml)
      write_schema(tmp, "skill", skill_yaml)
      schemas = described_class.new(tmp)
      names = schemas.all.map(&:name).sort
      expect(names).to eq(%w[agent skill])
    end
  end

  describe "#by_name" do
    it "maps each schema's canonical (file-stem) name to its Schema" do
      write_schema(tmp, "agent", agent_yaml)
      write_schema(tmp, "skill", skill_yaml)
      schemas = described_class.new(tmp)
      expect(schemas.by_name.keys.sort).to eq(%w[agent skill])
      expect(schemas.by_name["agent"]).to be_a(Textus::Schema)
    end

    it "keys on the file stem even when the schema body carries no name:" do
      write_schema(tmp, "nameless", "required: [x]\nfields:\n  x: { type: string }\n")
      schemas = described_class.new(tmp)
      expect(schemas.by_name.keys).to eq(["nameless"])
    end
  end

  describe "canon zone-kind (ADR 0033)" do
    it "accepts kind: canon and rejects the retired kind: origin" do
      canon = { "version" => "textus/4",
                "roles" => [{ "name" => "human", "can" => ["author"] }],
                "lanes" => [{ "name" => "knowledge", "kind" => "canon" }],
                "entries" => [] }
      expect { Textus::Manifest::Schema.validate!(canon) }.not_to raise_error

      origin = canon.merge("lanes" => [{ "name" => "knowledge", "kind" => "origin" }])
      expect { Textus::Manifest::Schema.validate!(origin) }
        .to raise_error(Textus::BadManifest, /unknown lane kind 'origin'|must be one of/)
    end
  end
end
