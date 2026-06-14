# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Textus::Surfaces::MCP::Server do
  let(:stdout) { StringIO.new }

  def make_server
    described_class.new(store: instance_double(Textus::Store), stdin: StringIO.new, stdout: stdout)
  end

  describe "message size guard" do
    it "emits a -32700 parse error for a line exceeding MAX_LINE_BYTES" do
      server = make_server
      oversized = "x" * (Textus::Surfaces::MCP::Server::MAX_LINE_BYTES + 1)
      server.send(:handle_line, oversized)
      response = JSON.parse(stdout.string.strip)
      expect(response["error"]["code"]).to eq(-32_700)
      expect(response["error"]["message"]).to match(/too large/)
    end

    it "does not raise for a line at exactly MAX_LINE_BYTES" do
      server = make_server
      at_limit = "x" * Textus::Surfaces::MCP::Server::MAX_LINE_BYTES
      server.send(:handle_line, at_limit)
      response = JSON.parse(stdout.string.strip)
      expect(response["error"]["code"]).to eq(-32_700)
      expect(response["error"]["message"]).to match(/parse error/)
    end
  end
end
