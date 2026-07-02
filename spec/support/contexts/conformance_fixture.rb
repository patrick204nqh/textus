RSpec.shared_context "textus/4 conformance fixture" do
  let(:tmp)  { Dir.mktmpdir("textus-spec") }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge/network/org"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge/projects"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge/constraint"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge/judgment"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge/evidence"))
    FileUtils.mkdir_p(File.join(root, "data/scratchpad/notes"))
    FileUtils.mkdir_p(File.join(root, "data/scratchpad/sessions"))
    FileUtils.mkdir_p(File.join(root, "data/scratchpad/scripts"))
    FileUtils.mkdir_p(File.join(root, "data/proposals/notes"))
    FileUtils.mkdir_p(File.join(root, "data/raw"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts/catalogs"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts/feeds/calendar"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      data:
        knowledge:
          - key: knowledge.network.org
            schema: person
          - key: knowledge.projects
          - key: knowledge.constraint
          - key: knowledge.judgment
          - key: knowledge.evidence
        scratchpad:
          - key: scratchpad.notes
            tracked: false
          - key: scratchpad.sessions
            tracked: false
          - key: scratchpad.scripts
            tracked: false
        proposals:
          - key: proposals.notes
        raw:
          - key: raw
            format: yaml
        artifacts:
          - key: artifacts.catalogs.skills
          - key: artifacts.feeds.calendar.events
    YAML

    File.write(File.join(root, "schemas/person.yaml"), <<~YAML)
      name: person
      required:
        - name
        - relationship
        - org
      optional:
        - notes
        - aliases
      fields:
        name:         { type: string, max: 80 }
        relationship: { type: enum, values: [peer, manager, report, external] }
        org:          { type: string }
        aliases:      { type: array, items: { type: string } }
        notes:        { type: string, max: 2000 }
    YAML

    File.write(File.join(root, "data/knowledge/network/org/jane.md"), <<~MD)
      ---
      name: jane
      relationship: peer
      org: acme
      ---
      Short body in Markdown.
    MD
  end

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }
end
