RSpec.shared_context "textus/3 conformance fixture" do
  let(:tmp)  { Dir.mktmpdir("textus-spec") }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge/network/org"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge/projects"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts/catalogs"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts/feeds/calendar"))
    FileUtils.mkdir_p(File.join(root, "data/identity"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: identity,  kind: canon }
        - { name: knowledge,   kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: identity.self,         path: identity/self,         lane: identity,   owner: human:patrick, kind: leaf}

        - { key: knowledge.network.org,   path: data/knowledge/network/org,   lane: knowledge,  schema: person, owner: human:patrick, kind: nested}

        - { key: knowledge.projects,      path: data/knowledge/projects,      lane: knowledge,    owner: human:patrick, kind: nested}

        - { key: artifacts.catalogs.skills, path: data/artifacts/catalogs/skills, lane: artifacts, owner: automation:catalog, kind: produced, source: { from: external, command: "rake catalog:skills", sources: [knowledge.projects] } }
        - key: artifacts.feeds.calendar.events
          kind: produced
          path: data/artifacts/feeds/calendar/events
          lane: artifacts
          owner: automation:cron
          source:
            from: fetch
            handler: http_json
            config: { url: "https://example.com/calendar.ics" }
            ttl: 300s
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
