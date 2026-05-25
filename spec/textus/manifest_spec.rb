require "spec_helper"

RSpec.describe Textus::Manifest do
  describe "textus/3 zone validation" do
    it "accepts intake as a canonical zone name" do
      yaml = <<~Y
        version: textus/3
        zones:
          - { name: intake, writable_by: [runner] }
        entries: []
      Y
      expect { described_class.parse(yaml) }.not_to raise_error
    end

    it "rejects legacy 'inbox' zone with a migration hint" do
      yaml = <<~Y
        version: textus/3
        zones:
          - { name: inbox, writable_by: [runner] }
        entries: []
      Y
      expect { described_class.parse(yaml) }
        .to raise_error(Textus::BadManifest, /inbox.*renamed to.*intake/i)
    end
  end
end
