require "spec_helper"

RSpec.describe Textus::Write::PublishRenderer do
  subject(:renderer) { described_class.new(template_loader: ->(_n) { "{{#entries}}{{key}}\n{{/entries}}" }) }

  let(:data) { { "entries" => [{ "key" => "k1" }, { "key" => "k2" }] } }

  it "renders entry data through the target template" do
    target = Textus::Domain::Policy::PublishTarget.new("to" => "OUT.md", "template" => "t")
    expect(renderer.bytes_for(target: target, data: data, boot: nil)).to eq("k1\nk2\n")
  end

  it "raises on a verbatim target (caller copies, not renders)" do
    target = Textus::Domain::Policy::PublishTarget.new("to" => "out.json")
    expect { renderer.bytes_for(target: target, data: data, boot: nil) }
      .to raise_error(ArgumentError, /verbatim/)
  end

  it "injects boot when asked" do
    r = described_class.new(template_loader: ->(_n) { "{{boot.greeting}}" })
    target = Textus::Domain::Policy::PublishTarget.new("to" => "OUT.md", "template" => "t", "inject_boot" => true)
    expect(r.bytes_for(target: target, data: {}, boot: { "greeting" => "hi" })).to eq("hi")
  end
end
