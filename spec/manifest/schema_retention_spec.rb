require "spec_helper"

RSpec.describe "Textus::Manifest::Schema retention block" do
  def parse(retention_yaml)
    raw = YAML.safe_load(<<~YAML, aliases: false)
      version: textus/3
      zones: [{ name: review, kind: queue, write_policy: [agent] }]
      entries: []
      rules:
        - match: review.**
          retention: #{retention_yaml}
    YAML
    Textus::Manifest::Schema.validate!(raw)
  end

  it "accepts expire_after and archive_after" do
    expect { parse("{ expire_after: 30d, archive_after: 7d }") }.not_to raise_error
  end

  it "rejects an unknown retention key" do
    expect { parse("{ purge_after: 30d }") }
      .to raise_error(Textus::BadManifest, /unknown key 'purge_after'/)
  end
end
