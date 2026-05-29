require "spec_helper"
require "stringio"
require "json"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::MCP::Server do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/review"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, kind: origin, write_policy: [human] }
        - { name: working,  kind: origin, write_policy: [human, agent] }
        - { name: review,   kind: origin, write_policy: [agent] }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }

  def run_requests(*messages)
    input = messages.map { |m| JSON.dump(m) }.join("\n") + "\n"
    output = StringIO.new
    described_class.new(store: store, stdin: StringIO.new(input), stdout: output).run
    output.string.lines.map { |l| JSON.parse(l) }
  end

  it "responds to initialize with serverInfo and protocolVersion" do
    responses = run_requests(
      { "jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
        "params" => { "protocolVersion" => "2024-11-05", "capabilities" => {}, "clientInfo" => { "name" => "test", "version" => "0" } } },
    )
    expect(responses.size).to eq(1)
    expect(responses[0]["id"]).to eq(1)
    expect(responses[0]["result"]).to include("serverInfo", "protocolVersion", "capabilities")
    expect(responses[0]["result"]["serverInfo"]["name"]).to eq("textus")
  end

  it "responds to tools/list with the static tool catalog" do
    responses = run_requests(
      { "jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
        "params" => { "protocolVersion" => "2024-11-05", "capabilities" => {}, "clientInfo" => { "name" => "t", "version" => "0" } } },
      { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => {} },
    )
    list = responses.find { |r| r["id"] == 2 }
    names = list["result"]["tools"].map { |t| t["name"] }
    expect(names).to include("boot", "tick", "find", "read", "write", "propose", "refresh", "refresh_stale", "schema", "rules")
  end

  it "executes tools/call('boot') and returns content" do
    responses = run_requests(
      { "jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
        "params" => { "protocolVersion" => "2024-11-05", "capabilities" => {}, "clientInfo" => { "name" => "t", "version" => "0" } } },
      { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/call", "params" => { "name" => "boot", "arguments" => {} } },
    )
    call_resp = responses.find { |r| r["id"] == 2 }
    expect(call_resp["result"]["isError"]).to be(false)
    body = JSON.parse(call_resp["result"]["content"][0]["text"])
    expect(body).to include("zones", "agent_quickstart")
  end

  it "returns ContractDrift JSON-RPC error when manifest changes between calls" do
    input1 = JSON.dump({ "jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                         "params" => { "protocolVersion" => "2024-11-05", "capabilities" => {},
                                       "clientInfo" => { "name" => "t", "version" => "0" } } })

    stdin_pipe_r, stdin_pipe_w = IO.pipe
    output = StringIO.new
    thread = Thread.new { described_class.new(store: store, stdin: stdin_pipe_r, stdout: output).run }

    stdin_pipe_w.puts(input1)
    sleep 0.2

    File.write(File.join(root, "manifest.yaml"), File.read(File.join(root, "manifest.yaml")) + "# touched\n")

    stdin_pipe_w.puts(JSON.dump({ "jsonrpc" => "2.0", "id" => 2, "method" => "tools/call",
                                  "params" => { "name" => "boot", "arguments" => {} } }))
    sleep 0.2
    stdin_pipe_w.close
    thread.join(2)

    lines = output.string.lines.map { |l| JSON.parse(l) }
    drift = lines.find { |r| r["id"] == 2 && r["error"] }
    expect(drift).not_to be_nil
    expect(drift["error"]["code"]).to eq(Textus::MCP::ContractDrift::JSONRPC_CODE)
  end

  it "returns method-not-found error for unknown methods" do
    responses = run_requests(
      { "jsonrpc" => "2.0", "id" => 1, "method" => "nope/whatever", "params" => {} },
    )
    expect(responses[0]["error"]["code"]).to eq(-32_601)
  end
end
