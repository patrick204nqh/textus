require "spec_helper"
require "tmpdir"

RSpec.describe "Textus::Manifest version mismatch hints" do
  it "points at 0.11.x when the manifest reports version: textus/2" do
    yaml = "version: textus/2\nzones: []\nentries: []\n"
    expect { Textus::Manifest.parse(yaml) }.to raise_error(Textus::BadFrontmatter) { |err|
      expect(err.message).to match(%r{unsupported manifest version "textus/2"})
      expect(err.hint).to match(/0\.11\.x/)
      expect(err.hint).not_to match(/syntax errors/)
    }
  end

  it "uses the generic hint for any other unsupported version" do
    yaml = "version: textus/4\nzones: []\nentries: []\n"
    expect { Textus::Manifest.parse(yaml) }.to raise_error(Textus::BadFrontmatter) { |err|
      expect(err.message).to match(%r{unsupported manifest version "textus/4"})
      expect(err.hint).to match(/syntax errors/)
      expect(err.hint).not_to match(/0\.11\.x/)
    }
  end

  it "also emits the 0.11.x hint via Manifest.load (file path branch)" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "manifest.yaml"), "version: textus/2\nzones: []\nentries: []\n")
      expect { Textus::Manifest.load(dir) }.to raise_error(Textus::BadFrontmatter) { |err|
        expect(err.hint).to match(/0\.11\.x/)
      }
    end
  end
end
