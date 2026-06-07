require "spec_helper"

RSpec.describe "session contract" do
  describe "drift" do
    let(:tmp)  { Dir.mktmpdir }
    let(:root) { File.join(tmp, ".textus") }

    before do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
      FileUtils.mkdir_p(File.join(root, "hooks"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones: [{ name: knowledge, kind: canon }]
        entries:
          - { key: knowledge.x, path: knowledge/x.md, zone: knowledge, kind: leaf }
      YAML
      File.write(File.join(root, "hooks/a.rb"), "Textus.hook { |reg| }\n")
    end

    after { FileUtils.remove_entry(tmp) }

    def observed(store)
      Textus::Etag.for_contract(store.root)
    end

    it "raises ContractDrift when a hook file changes mid-session" do
      store   = Textus::Store.new(root)
      session = store.session(role: :agent)

      File.write(File.join(root, "hooks/a.rb"), "Textus.hook { |reg| } # edited\n")

      expect { session.check_etag!(observed(store)) }
        .to raise_error(Textus::MCP::ContractDrift, %r{manifest/hooks/schemas})
    end

    it "does not raise when nothing changed" do
      store   = Textus::Store.new(root)
      session = store.session(role: :agent)
      expect { session.check_etag!(observed(store)) }.not_to raise_error
    end
  end

  describe "RoleScope maintenance surface" do
    include_context "textus_store_fixture"

    before do
      %w[zones/working schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, kind: canon }
        entries:
          - { key: working.note, path: working/note.md, zone: working, owner: human:self, kind: leaf }
      YAML
      FileUtils.mkdir_p(audit_dir_path(root))
      File.write(audit_log_path(root), "")
    end

    let(:store) { Textus::Store.new(root) }
    let(:sess)  { store.as("human") }

    it "exposes key_mv_prefix, key_delete_prefix, zone_mv, rule_lint" do
      %i[key_mv_prefix key_delete_prefix zone_mv rule_lint].each do |m|
        expect(sess).to respond_to(m)
      end
    end
  end
end
