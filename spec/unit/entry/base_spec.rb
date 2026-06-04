require "spec_helper"

RSpec.describe Textus::Entry::Base do
  it "raises NotImplementedError on parse" do
    expect { described_class.parse("x", path: "/tmp/x") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError on serialize" do
    expect { described_class.serialize(meta: {}, body: "") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError on extensions" do
    expect { described_class.extensions }.to raise_error(NotImplementedError)
  end

  describe "validate_against" do
    let(:schema) { instance_double(Textus::Schema, validate!: true) }

    it "is overridable per format" do
      stub = Class.new(described_class) do
        def self.validate_against(schema, _parsed)
          schema.validate!({ "stub" => true })
        end
      end
      stub.validate_against(schema, { "_meta" => {} })
      expect(schema).to have_received(:validate!).with({ "stub" => true })
    end
  end
end
