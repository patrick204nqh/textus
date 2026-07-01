require "spec_helper"
require "stringio"

RSpec.describe Textus::Surface::MCP::Server do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/identity"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/proposals"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: identity, kind: canon }
        - { name: knowledge,  kind: canon }
        - { name: proposals,   kind: queue }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
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
    # propose/schema/rules are composed tools promoted in Phase C (ADR 0039)
    expect(names).to include("boot", "pulse", "list", "get", "put", "drain")
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
    expect(body).to include("lanes", "agent_quickstart")
  end

  it "returns contract_drifted flag in pulse response when manifest changes between calls" do
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
                                  "params" => { "name" => "pulse", "arguments" => {} } }))
    sleep 0.2
    stdin_pipe_w.close
    thread.join(2)

    lines = output.string.lines.map { |l| JSON.parse(l) }
    resp = lines.find { |r| r["id"] == 2 }
    expect(resp["error"]).to be_nil
    body = JSON.parse(resp["result"]["content"][0]["text"])
    expect(body["contract_drifted"]).to be(true)
  end

  # ADR 0083 — contract-drift guard gates write verbs only

  # Helper: run an initialize + optional pre-drift setup, write a schema file
  # to simulate drift, then send one more tools/call. Returns [lines, drift_file].
  def run_with_drift(name:, arguments: {})
    input1 = JSON.dump({ "jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                         "params" => { "protocolVersion" => "2024-11-05", "capabilities" => {},
                                       "clientInfo" => { "name" => "t", "version" => "0" } } })

    stdin_pipe_r, stdin_pipe_w = IO.pipe
    output = StringIO.new
    thread = Thread.new { described_class.new(store: store, stdin: stdin_pipe_r, stdout: output).run }

    stdin_pipe_w.puts(input1)
    sleep 0.2

    # Simulate contract drift by adding a new schema file
    File.write(File.join(root, "schemas", "drift_test.yaml"), "fields: {}\n")

    stdin_pipe_w.puts(JSON.dump({ "jsonrpc" => "2.0", "id" => 2, "method" => "tools/call",
                                  "params" => { "name" => name, "arguments" => arguments } }))
    sleep 0.2
    stdin_pipe_w.close
    thread.join(2)

    output.string.lines.map { |l| JSON.parse(l) }
  end

  it "includes a soft warning on write verb (put) after contract drift (no hard error)" do
    lines = run_with_drift(name: "put",
                           arguments: { "key" => "knowledge.note", "body" => "hello",
                                        "meta" => { "owner" => "human:self" } })
    resp = lines.find { |r| r["id"] == 2 }
    expect(resp["error"]).to be_nil
    body = JSON.parse(resp["result"]["content"][0]["text"])
    expect(body).to include("_warning")
    expect(body["_warning"]).to include("contract drifted")
  end

  it "allows a read verb (list) after contract drift without error" do
    lines = run_with_drift(name: "list", arguments: {})
    resp = lines.find { |r| r["id"] == 2 }
    expect(resp["error"]).to be_nil
    expect(resp["result"]["isError"]).to be(false)
  end

  it "allows boot after contract drift and re-arms the session so a subsequent write succeeds" do
    put_args = { "key" => "knowledge.note", "body" => "hello", "meta" => { "owner" => "human:self" } }
    stdin_pipe_r, stdin_pipe_w = IO.pipe
    output = StringIO.new
    thread = Thread.new { described_class.new(store: store, stdin: stdin_pipe_r, stdout: output).run }
    stdin_pipe_w.puts(JSON.dump({ "jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                                  "params" => { "protocolVersion" => "2024-11-05", "capabilities" => {},
                                                "clientInfo" => { "name" => "t", "version" => "0" } } }))
    sleep 0.2
    File.write(File.join(root, "schemas", "drift_rearm.yaml"), "fields: {}\n")
    stdin_pipe_w.puts(JSON.dump({ "jsonrpc" => "2.0", "id" => 2, "method" => "tools/call",
                                  "params" => { "name" => "boot", "arguments" => {} } }))
    sleep 0.2
    stdin_pipe_w.puts(JSON.dump({ "jsonrpc" => "2.0", "id" => 3, "method" => "tools/call",
                                  "params" => { "name" => "put", "arguments" => put_args } }))
    sleep 0.2
    stdin_pipe_w.close
    thread.join(2)
    lines = output.string.lines.map { |l| JSON.parse(l) }
    boot_resp  = lines.find { |r| r["id"] == 2 }
    write_resp = lines.find { |r| r["id"] == 3 }
    expect(boot_resp["error"]).to be_nil
    expect(boot_resp["result"]["isError"]).to be(false)
    expect(write_resp["error"]).to be_nil
    expect(write_resp["result"]["isError"]).to be(false)
  end

  it "includes a soft warning on drain after contract drift (no hard error)" do
    lines = run_with_drift(name: "drain", arguments: {})
    resp = lines.find { |r| r["id"] == 2 }
    expect(resp["error"]).to be_nil
    body = JSON.parse(resp["result"]["content"][0]["text"])
    expect(body).to include("_warning")
    expect(body["_warning"]).to include("contract drifted")
  end

  it "returns method-not-found error for unknown methods" do
    responses = run_requests(
      { "jsonrpc" => "2.0", "id" => 1, "method" => "nope/whatever", "params" => {} },
    )
    expect(responses[0]["error"]["code"]).to eq(-32_601)
  end
end
