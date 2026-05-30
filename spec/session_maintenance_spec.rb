require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Textus::RoleScope maintenance surface" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/working schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: canon }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:sess)  { store.as("human") }

  it "exposes key_mv_prefix, key_delete_prefix, zone_mv, rule_lint, migrate" do
    %i[key_mv_prefix key_delete_prefix zone_mv rule_lint migrate].each do |m|
      expect(sess).to respond_to(m)
    end
  end
end
