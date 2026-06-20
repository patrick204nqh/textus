require "spec_helper"

RSpec.describe "tracked:false entries drive a derived .gitignore" do
  it "includes an untracked entry's path and the run subtree" do
    body = Textus::Store::Geometry.new("test").gitignore_body(untracked_entries: ["data/feeds/machine.md"])
    expect(body).to include("#{Textus::Store::Geometry::RUN}/")
    expect(body).to include("data/feeds/machine.md")
  end

  it "defaults entries to tracked: true" do
    expect(Textus::Manifest::Schema::ENTRY_KEYS).to include("tracked")
  end
end
