require "spec_helper"

RSpec.describe "Entry strategy: nested_glob" do
  it "returns the right pattern for each format" do
    expect(Textus::Entry::Markdown.nested_glob).to eq("**/*.md")
    expect(Textus::Entry::Json.nested_glob).to eq("**/*.json")
    expect(Textus::Entry::Yaml.nested_glob).to eq("**/*.{yaml,yml}")
    expect(Textus::Entry::Text.nested_glob).to eq("**/*.txt")
  end

  it "Base raises NotImplementedError" do
    expect { Textus::Entry::Base.nested_glob }.to raise_error(NotImplementedError)
  end
end
