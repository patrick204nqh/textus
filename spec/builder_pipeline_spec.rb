require "spec_helper"
require "tempfile"

RSpec.describe Textus::Builder::Renderer::Markdown do
  let(:mentry) do
    instance_double(
      Textus::Manifest::Entry::Derived,
      format: "markdown", template: "tpl.md.mustache",
      source: Textus::Manifest::Entry::Derived::Projection.new(
        select: ["working.*"], pluck: nil, sort_by: nil, transform: nil,
      ),
      inject_boot: false
    )
  end

  it "renders body via mustache and serializes with generated frontmatter" do
    tpl_path = Tempfile.new(["tpl", ".mustache"])
    tpl_path.write("Hello {{name}}")
    tpl_path.close
    renderer = described_class.new(template_loader: ->(_) { File.read(tpl_path.path) })

    bytes = renderer.call(mentry: mentry, data: { "name" => "world" })

    expect(bytes).to include("Hello world")
    expect(bytes).to match(/^---\n/) # YAML frontmatter
    expect(bytes).to include("generated:")
    expect(bytes).to include("at:")
  ensure
    tpl_path&.unlink
  end
end
