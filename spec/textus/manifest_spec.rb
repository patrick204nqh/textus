require "spec_helper"
require "tmpdir"

RSpec.describe "Textus::Manifest version mismatch hints" do
  it "raises BadFrontmatter with the generic hint for any unsupported version" do
    yaml = "version: textus/4\nzones: []\nentries: []\n"
    expect { Textus::Manifest.parse(yaml) }.to raise_error(Textus::BadFrontmatter) { |err|
      expect(err.message).to match(%r{unsupported manifest version "textus/4"})
      expect(err.hint).to match(/syntax errors/)
      expect(err.hint).not_to match(/0\.11\.x/)
    }
  end
end
