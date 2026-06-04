require "spec_helper"

RSpec.describe Textus::Manifest::Schema do
  def validate!(rules)
    described_class.validate!(
      "version" => "textus/3",
      "zones" => [{ "name" => "feeds", "kind" => "quarantine" }],
      "entries" => [],
      "rules" => rules,
    )
  end

  it "accepts a lifecycle block with ttl + on_expire" do
    expect do
      validate!([{ "match" => "feeds.*", "lifecycle" => { "ttl" => "1h", "on_expire" => "refresh" } }])
    end.not_to raise_error
  end

  it "rejects an unknown key inside lifecycle" do
    expect do
      validate!([{ "match" => "feeds.*", "lifecycle" => { "ttl" => "1h", "bogus" => 1 } }])
    end.to raise_error(Textus::BadManifest, /unknown key 'bogus' at '\$\.rules\[0\]\.lifecycle'/)
  end
end
