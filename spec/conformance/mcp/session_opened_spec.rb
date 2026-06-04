require "spec_helper"
require "json"
require "stringio"

# rubocop:disable Style/GlobalVars
RSpec.describe "MCP :session_opened event" do
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
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $textus_session_log ||= []
      Textus.hook do |reg|
        reg.on(:session_opened, :log_opened) do |role:, cursor:, **|
          $textus_session_log << [role.to_s, cursor]
        end
      end
    RUBY
    $textus_session_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_session_log = nil
  end

  def run_server(role:, messages:)
    store  = Textus::Store.new(root)
    stdin  = StringIO.new(messages.map { |m| JSON.dump(m) }.join("\n") + "\n")
    Textus::MCP::Server.new(store: store, stdin: stdin, stdout: StringIO.new, role: role).run
  end

  it "fires :session_opened once at initialize with the resolved role and cursor" do
    run_server(role: "agent", messages: [
                 { "jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => {} },
               ])
    expect($textus_session_log.length).to eq(1)
    role, cursor = $textus_session_log.first
    expect(role).to eq("agent")
    expect(cursor).to be_a(Integer)
  end

  it "carries the overridden role when launched --as=human" do
    run_server(role: "human", messages: [
                 { "jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => {} },
               ])
    expect($textus_session_log.first.first).to eq("human")
  end

  it "does not fire again on a subsequent tools/call" do
    run_server(role: "agent", messages: [
                 { "jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => {} },
                 { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/call",
                   "params" => { "name" => "list", "arguments" => {} } },
               ])
    expect($textus_session_log.length).to eq(1)
  end
end
# rubocop:enable Style/GlobalVars
