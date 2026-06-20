# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"

RSpec.describe "MCP resources surface" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[artifacts], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: agent, can: [propose] }
        - { name: automation, can: [converge] }
      lanes:
        - { name: artifacts, kind: machine }
      entries:
        - key: artifacts.system.index
          lane: artifacts
          kind: produced
          format: json
          source: { from: external, command: "true", sources: [] }
    YAML
  end

  def mcp_exchange(store, method, params = {})
    req_id = 1
    stdin  = StringIO.new
    stdout = StringIO.new
    server = Textus::Surface::MCP::Server.new(store: store, stdin: stdin, stdout: stdout, role: "agent")

    init_msg = JSON.dump({ "jsonrpc" => "2.0", "id" => 0, "method" => "initialize", "params" => {} })
    stdin.string = init_msg + "\n" + JSON.dump({ "jsonrpc" => "2.0", "id" => req_id, "method" => method, "params" => params }) + "\n"
    stdin.rewind
    server.run
    lines = stdout.string.strip.split("\n")
    JSON.parse(lines.last)
  end

  it "resources/list returns all produced machine-lane entries as resources" do
    result = mcp_exchange(store, "resources/list")
    resources = result.dig("result", "resources")
    expect(resources).to be_an(Array)
    uris = resources.map { |r| r["uri"] }
    expect(uris).to include("textus://artifacts/system/index")
  end

  it "each resource has uri, name, and mimeType" do
    result = mcp_exchange(store, "resources/list")
    resources = result.dig("result", "resources")
    resources.each do |r|
      expect(r).to include("uri", "name", "mimeType")
      expect(r["uri"]).to start_with("textus://")
    end
  end

  it "resources/read returns content of an existing artifact" do
    path = File.join(root, "data/artifacts/system/index.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.dump({ "entries" => [], "generated_at" => "2026-06-16T00:00:00Z" }))

    result = mcp_exchange(store, "resources/read", { "uri" => "textus://artifacts/system/index" })
    contents = result.dig("result", "contents")
    expect(contents).to be_an(Array)
    expect(contents.first["uri"]).to eq("textus://artifacts/system/index")
    expect(contents.first["text"]).to be_a(String)
  end
end
