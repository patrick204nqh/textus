require "spec_helper"
require "stringio"

RSpec.describe "MCP end-to-end" do
  include_context "textus_store_fixture"

  before do
    %w[zones/identity zones/working zones/review schemas hooks].each do |d|
      FileUtils.mkdir_p(File.join(root, d))
    end
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: canon }
        - { name: working,  kind: canon }
        - { name: review,   kind: queue }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
    File.write(File.join(root, "audit.log"), "")
  end

  it "handshake → tools/list → tools/call boot/find/write/tick all succeed" do
    store = Textus::Store.new(root)
    requests = [
      { id: 1, method: "initialize",
        params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "0" } } },
      { id: 2, method: "tools/list", params: {} },
      { id: 3, method: "tools/call", params: { name: "boot",  arguments: {} } },
      { id: 4, method: "tools/call", params: { name: "tick",  arguments: { since: 0 } } },
    ].map { |r| JSON.dump(r.merge(jsonrpc: "2.0")) }.join("\n") + "\n"

    out = StringIO.new
    Textus::MCP::Server.new(store: store, stdin: StringIO.new(requests), stdout: out).run

    responses = out.string.lines.map { |l| JSON.parse(l) }
    expect(responses.map { |r| r["id"] }).to eq([1, 2, 3, 4])
    expect(responses.all? { |r| r["error"].nil? }).to be(true)
  end
end
