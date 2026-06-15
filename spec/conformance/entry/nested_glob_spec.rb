require "spec_helper"

RSpec.describe "Entry strategy: nested_glob" do
  it "returns the right pattern for each format" do
    expect(Textus::Format::Markdown.nested_glob).to eq("**/*.md")
    expect(Textus::Format::Json.nested_glob).to eq("**/*.json")
    expect(Textus::Format::Yaml.nested_glob).to eq("**/*.{yaml,yml}")
    expect(Textus::Format::Text.nested_glob).to eq("**/*.txt")
  end

  it "Base raises NotImplementedError" do
    expect { Textus::Format::Base.nested_glob }.to raise_error(NotImplementedError)
  end
end
