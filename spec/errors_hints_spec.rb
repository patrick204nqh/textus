require "spec_helper"

RSpec.describe "Textus error hints" do
  it "UnknownKey hint mentions suggestions when present" do
    err = Textus::UnknownKey.new("working.x", suggestions: ["working.y", "working.z"])
    expect(err.hint).to be_a(String)
    expect(err.hint).not_to be_empty
    expect(err.hint).to include("working.y")
  end

  it "UnknownKey hint falls back to a useful suggestion when no candidates" do
    err = Textus::UnknownKey.new("working.x")
    expect(err.hint).to be_a(String)
    expect(err.hint).to include("textus list")
  end

  it "BadFrontmatter hint includes both names when name/basename mismatch" do
    err = Textus::BadFrontmatter.new(
      "/tmp/jane.md",
      "name 'janet' does not match basename 'jane'",
    )
    expect(err.hint).to be_a(String)
    expect(err.hint).to include("janet")
    expect(err.hint).to include("jane")
  end

  it "BadContent hint mentions parsing tools" do
    err = Textus::BadContent.new("/tmp/x.json", "parse fail")
    expect(err.hint).to include("jq").or include("yq")
  end

  it "WriteForbidden hint mentions the writers role list when supplied" do
    err = Textus::WriteForbidden.new("canon.identity", "canon", writers: ["human"])
    expect(err.hint).to be_a(String)
    expect(err.hint).to include("human")
    expect(err.hint).to include("--as")
  end

  it "EtagMismatch hint suggests fetching the latest etag and mentions the key" do
    err = Textus::EtagMismatch.new("working.x", "sha256:aa", "sha256:bb")
    expect(err.hint).to include("working.x")
    expect(err.hint).to include("textus get")
  end

  it "PublishError hint mentions the target path when supplied" do
    err = Textus::PublishError.new("nope", target: "/repo/CLAUDE.md")
    expect(err.hint).to be_a(String)
    expect(err.hint).to include("/repo/CLAUDE.md")
  end

  it "TemplateError hint mentions the template name when supplied" do
    err = Textus::TemplateError.new("missing", template_name: "foo.mustache")
    expect(err.hint).to be_a(String)
    expect(err.hint).to include("foo.mustache")
  end

  it "BadRender hint mentions the rendered format" do
    err = Textus::BadRender.new("oops", format: "json")
    expect(err.hint).to be_a(String)
    expect(err.hint).to include("json")
  end

  it "SchemaViolation hint surfaces missing fields when present in details" do
    err = Textus::SchemaViolation.new("missing" => %w[relationship org])
    expect(err.hint).to be_a(String)
    expect(err.hint).to include("relationship")
  end

  it "to_envelope includes the hint when present" do
    err = Textus::UnknownKey.new("a.b", suggestions: ["a.c"])
    expect(err.to_envelope["hint"]).to eq(err.hint)
  end
end
