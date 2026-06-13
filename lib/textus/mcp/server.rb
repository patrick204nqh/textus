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
        # The acting role IS the resolved connection role (ADR 0040): the MCP
        # transport defaults to `agent`, which can write the queue, so its
        # propose_zone resolves directly. If a connection's role cannot propose,
        # propose_zone is nil and the `propose` tool reports that honestly.
        propose_zone = @store.manifest.policy.propose_zone_for(@role)

        @session = Session.new(
          role: @role,
          cursor: @store.audit_log.latest_seq,
          propose_zone: propose_zone,
          contract_etag: contract_etag,
        )

        # ADR 0075: announce the connection to connect-time hooks with the
        # resolved role. Distinct from :store_loaded (fired at Store.new under
        # the default role, before any connection's role is known).
        @store.steps.publish(
          :session_opened,
          ctx: Step::Context.new(scope: @store.as(@role)),
          role: @role,
          cursor: @session.cursor,
        )

        emit_result(rid, {
                      "protocolVersion" => PROTOCOL_VERSION,
                      "serverInfo" => SERVER_INFO,
                      "capabilities" => { "tools" => {} },
                    })
      end

      def handle_tools_list(rid)
        emit_result(rid, { "tools" => Catalog.tool_schemas })
      end

      def handle_tools_call(rid, params)
        unless @session
          emit_error(rid, -32_002, "session not initialized; call 'initialize' first")
          return
        end

        name = params["name"]
        args = params["arguments"] || {}

        # ADR 0083: the contract-drift guard gates mutating verbs — every MCP
        # verb that is NOT a pure read (Write:: + the destructive Maintenance::
        # verbs drain/data_mv/key_*_prefix). Reads and boot bypass it (a stale
        # read returns on-disk truth; boot re-orients). Keying on read_verbs
        # (not write_verbs) keeps the destructive Maintenance:: verbs gated.
        @session.check_etag!(contract_etag) unless Catalog.read_verbs.include?(name)

        result = Catalog.call(name, session: @session, store: @store, args: args)
        @session = @session.advance_cursor(@store.audit_log.latest_seq) if name == "pulse"
        @session = @session.with(contract_etag: contract_etag) if name == "boot"

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

      def contract_etag
        Textus::Etag.for_contract(@store.root)
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
