require "json"

module Textus
  module MCP
    # Stdio JSON-RPC 2.0 server speaking MCP draft 2024-11-05. One line per
    # message (NDJSON). Holds a single Session for the lifetime of stdin.
    class Server
      PROTOCOL_VERSION = "2024-11-05"
      SERVER_INFO = { "name" => "textus", "version" => Textus::VERSION }.freeze

      def initialize(store:, stdin: $stdin, stdout: $stdout, role: Textus::Role::DEFAULT)
        @store   = store
        @stdin   = stdin
        @stdout  = stdout
        @role    = role
        @session = nil
      end

      def run
        @stdin.each_line do |line|
          line = line.strip
          next if line.empty?

          handle_line(line)
        end
      end

      private

      def handle_line(line)
        msg = JSON.parse(line)
      rescue JSON::ParserError => e
        emit_error(nil, -32_700, "parse error: #{e.message}")
      else
        dispatch(msg)
      end

      def dispatch(msg)
        rid = msg["id"]
        case msg["method"]
        when "initialize"                then handle_initialize(rid, msg["params"] || {})
        when "tools/list"                then handle_tools_list(rid)
        when "tools/call"                then handle_tools_call(rid, msg["params"] || {})
        when "ping"                      then emit_result(rid, {})
        when "shutdown"                  then emit_result(rid, nil)
        when "notifications/initialized" then nil
        else emit_error(rid, -32_601, "method not found: #{msg["method"]}")
        end
      end

      def handle_initialize(rid, _params)
        proposer = @store.manifest.policy.roles_with_capability("propose").first
        propose_zone = @store.manifest.policy.propose_zone_for(proposer)

        @session = Session.new(
          role: @role,
          cursor: @store.audit_log.latest_seq,
          propose_zone: propose_zone,
          manifest_etag: manifest_etag,
        )

        emit_result(rid, {
                      "protocolVersion" => PROTOCOL_VERSION,
                      "serverInfo" => SERVER_INFO,
                      "capabilities" => { "tools" => {} },
                    })
      end

      def handle_tools_list(rid)
        emit_result(rid, { "tools" => ToolSchemas.all })
      end

      def handle_tools_call(rid, params)
        unless @session
          emit_error(rid, -32_002, "session not initialized; call 'initialize' first")
          return
        end

        @session.check_etag!(manifest_etag)

        name = params["name"]
        args = params["arguments"] || {}
        result = Tools.call(name, session: @session, store: @store, args: args)
        @session = @session.advance_cursor(@store.audit_log.latest_seq) if name == "tick"

        emit_result(rid, {
                      "content" => [{ "type" => "text", "text" => JSON.dump(result) }],
                      "isError" => false,
                    })
      rescue ContractDrift => e
        emit_error(rid, ContractDrift::JSONRPC_CODE, e.message)
      rescue CursorExpired => e
        emit_error(rid, CursorExpired::JSONRPC_CODE, e.message)
      rescue ToolError => e
        emit_error(rid, ToolError::JSONRPC_CODE, e.message)
      rescue StandardError => e
        emit_error(rid, -32_603, "internal: #{e.class}: #{e.message}")
      end

      def manifest_etag
        @store.file_store.etag(File.join(@store.root, "manifest.yaml"))
      end

      def emit_result(rid, result)
        write({ "jsonrpc" => "2.0", "id" => rid, "result" => result })
      end

      def emit_error(rid, code, message)
        write({ "jsonrpc" => "2.0", "id" => rid, "error" => { "code" => code, "message" => message } })
      end

      def write(obj)
        @stdout.puts(JSON.dump(obj))
        @stdout.flush
      end
    end
  end
end
