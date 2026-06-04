require "spec_helper"

RSpec.describe "Entry strategy: enforce_name_match!" do
  describe "Markdown" do
    it "no-ops when meta has no name" do
      expect { Textus::Entry::Markdown.enforce_name_match!("/x/foo.md", { "other" => 1 }) }.not_to raise_error
    end

    it "no-ops when meta.name matches basename" do
      expect { Textus::Entry::Markdown.enforce_name_match!("/x/foo.md", { "name" => "foo" }) }.not_to raise_error
    end

    it "raises when meta.name differs" do
      expect { Textus::Entry::Markdown.enforce_name_match!("/x/foo.md", { "name" => "bar" }) }
        .to raise_error(Textus::BadFrontmatter, /name 'bar' does not match basename 'foo'/)
    end
  end

  describe "Text" do
    it "is a no-op (text has no meta name)" do
      expect { Textus::Entry::Text.enforce_name_match!("/x/foo.txt", { "name" => "anything" }) }.not_to raise_error
    end
  end
end
