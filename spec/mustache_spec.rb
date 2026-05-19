require "spec_helper"

RSpec.describe Textus::Mustache do
  it "renders variables" do
    expect(Textus::Mustache.render("Hello {{name}}!", { "name" => "world" }))
      .to eq("Hello world!")
  end

  it "renders sections over arrays" do
    tpl = "{{#items}}- {{name}}\n{{/items}}"
    out = Textus::Mustache.render(tpl, { "items" => [{ "name" => "a" }, { "name" => "b" }] })
    expect(out).to eq("- a\n- b\n")
  end

  it "renders sections over truthy values" do
    tpl = "{{#flag}}yes{{/flag}}{{^flag}}no{{/flag}}"
    expect(Textus::Mustache.render(tpl, { "flag" => true })).to eq("yes")
    expect(Textus::Mustache.render(tpl, { "flag" => false })).to eq("no")
  end

  it "strips comments" do
    expect(Textus::Mustache.render("a{{! ignored }}b", {})).to eq("ab")
  end

  it "raises on missing variable in strict mode" do
    expect { Textus::Mustache.render("{{missing}}", {}, strict: true) }
      .to raise_error(Textus::TemplateError, /missing/)
  end

  it "rejects recursion deeper than 8" do
    deep = (1..9).reduce("x") { |acc, _| "{{#a}}#{acc}{{/a}}" }
    expect { Textus::Mustache.render(deep, { "a" => [{ "a" => [{}] }] }) }
      .to raise_error(Textus::TemplateError, /depth/)
  end
end
