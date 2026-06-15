require "spec_helper"

RSpec.describe "Entry strategy: validate_path_extension" do
  describe "Markdown" do
    it "accepts .md extension" do
      expect { Textus::Format::Markdown.validate_path_extension("foo.md", false) }.not_to raise_error
    end

    it "accepts no extension (markdown is default)" do
      expect { Textus::Format::Markdown.validate_path_extension("foo", false) }.not_to raise_error
    end

    it "rejects .json extension" do
      expect { Textus::Format::Markdown.validate_path_extension("foo.json", false) }
        .to raise_error(Textus::UsageError, /markdown format requires/)
    end
  end

  describe "Json" do
    it "non-nested: accepts .json extension" do
      expect { Textus::Format::Json.validate_path_extension("foo.json", false) }.not_to raise_error
    end

    it "non-nested: rejects no extension" do
      expect { Textus::Format::Json.validate_path_extension("foo", false) }
        .to raise_error(Textus::UsageError, /json format requires/)
    end

    it "nested: rejects any extension" do
      expect { Textus::Format::Json.validate_path_extension("foo.json", true) }
        .to raise_error(Textus::UsageError, /nested json path must not have an extension/)
    end

    it "nested: accepts no extension" do
      expect { Textus::Format::Json.validate_path_extension("foo", true) }.not_to raise_error
    end
  end

  describe "Yaml" do
    it "accepts .yaml and .yml non-nested" do
      expect { Textus::Format::Yaml.validate_path_extension("foo.yaml", false) }.not_to raise_error
      expect { Textus::Format::Yaml.validate_path_extension("foo.yml", false) }.not_to raise_error
    end

    it "rejects non-nested without extension" do
      expect { Textus::Format::Yaml.validate_path_extension("foo", false) }
        .to raise_error(Textus::UsageError, /yaml format requires/)
    end

    it "rejects nested with extension" do
      expect { Textus::Format::Yaml.validate_path_extension("foo.yaml", true) }
        .to raise_error(Textus::UsageError, /nested yaml path must not have an extension/)
    end
  end

  describe "Text" do
    it "non-nested: accepts .txt or no extension" do
      expect { Textus::Format::Text.validate_path_extension("foo.txt", false) }.not_to raise_error
      expect { Textus::Format::Text.validate_path_extension("foo", false) }.not_to raise_error
    end

    it "non-nested: rejects .md extension" do
      expect { Textus::Format::Text.validate_path_extension("foo.md", false) }
        .to raise_error(Textus::UsageError, /text format requires/)
    end

    it "nested: rejects extension" do
      expect { Textus::Format::Text.validate_path_extension("foo.txt", true) }
        .to raise_error(Textus::UsageError, /nested text path must not have an extension/)
    end
  end
end
