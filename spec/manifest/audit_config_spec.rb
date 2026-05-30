require "spec_helper"

RSpec.describe Textus::Manifest, "#audit_config" do
  def manifest_from(yaml)
    Textus::Manifest.parse(yaml)
  end

  it "defaults to max_size 10485760 (10MB) and keep 5 when audit: is absent" do
    m = manifest_from(<<~YAML)
      version: textus/3
      zones: [{ name: working, kind: origin }]
      entries: []
    YAML
    expect(m.data.audit_config).to eq(max_size: 10_485_760, keep: 5)
  end

  it "reads max_size and keep from manifest" do
    m = manifest_from(<<~YAML)
      version: textus/3
      audit:
        max_size: 1048576
        keep: 3
      zones: [{ name: working, kind: origin }]
      entries: []
    YAML
    expect(m.data.audit_config).to eq(max_size: 1_048_576, keep: 3)
  end

  it "rejects unknown audit: keys" do
    expect do
      manifest_from(<<~YAML)
        version: textus/3
        audit: { bogus: 1 }
        zones: [{ name: working, kind: origin }]
        entries: []
      YAML
    end.to raise_error(Textus::BadManifest, /unknown key 'bogus'/)
  end
end
