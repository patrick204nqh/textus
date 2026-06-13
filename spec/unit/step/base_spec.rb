# spec/unit/step/base_spec.rb
require "spec_helper"

RSpec.describe Textus::Step::Base do
  it "exposes kind and required_kwargs per subclass" do
    expect(Textus::Step::Fetch.kind).to eq(:fetch)
    expect(Textus::Step::Fetch.required_kwargs).to eq(%i[config args])
    expect(Textus::Step::Transform.kind).to eq(:transform)
    expect(Textus::Step::Transform.required_kwargs).to eq(%i[rows config])
    expect(Textus::Step::Validate.kind).to eq(:validate)
    expect(Textus::Step::Observe.kind).to eq(:observe)
  end

  it "lets a subclass override its registered name (for hyphenated built-ins)" do
    klass = Class.new(Textus::Step::Fetch) { step_name "markdown-links" }
    expect(klass.step_name).to eq("markdown-links")
  end

  it "carries an instance name assigned at registration" do
    inst = Textus::Step::Fetch.new
    inst.name = :authority
    expect(inst.name).to eq(:authority)
  end

  it "Observe declares its event and optional match glob" do
    klass = Class.new(Textus::Step::Observe) do
      on :entry_published
      match "docs.**"
    end
    expect(klass.event).to eq(:entry_published)
    expect(klass.match).to eq("docs.**")
  end
end
