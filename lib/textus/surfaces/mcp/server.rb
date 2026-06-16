require "json"

module Textus
  module Surfaces
    module MCP
      # Stdio JSON-RPC 2.0 server speaking MCP draft 2024-11-05. One line per
      # message (NDJSON). Holds a single Session for the lifetime of stdin.
      class Server
        PROTOCOL_VERSION = "2024-11-05"
        SERVER_INFO = { "name" => "textus", "version" => Textus::VERSION }.freeze
        MAX_LINE_BYTES = 1_048_576 # 1 MB — protects against OOM from oversized tool calls

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
          if line.bytesize > MAX_LINE_BYTES
            emit_error(nil, -32_700, "message too large (#{line.bytesize} bytes, limit #{MAX_LINE_BYTES})")
            return
          end
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
          when "resources/list"            then handle_resources_list(rid)
          when "resources/read"            then handle_resources_read(rid, msg["params"] || {})
          else emit_error(rid, -32_601, "method not found: #{msg["method"]}")
          end
        end

        def handle_initialize(rid, _params)
          # The acting role IS the resolved connection role (ADR 0040): the MCP
          # transport defaults to `agent`, which can write the queue, so its
          # propose_lane resolves directly. If a connection's role cannot propose,
          # propose_lane is nil and the `propose` tool reports that honestly.
          propose_lane = @store.manifest.policy.propose_lane_for(@role)

          @session = Session.new(
            role: @role,
            cursor: @store.audit_log.latest_seq,
            propose_lane: propose_lane,
            contract_etag: contract_etag,
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

        def handle_resources_list(rid)
          machine_lane = @store.manifest.policy.machine_lane
          resources = []
          if machine_lane
            @store.manifest.data.entries
                  .select { |e| e.lane == machine_lane && e.is_a?(Textus::Manifest::Entry::Produced) }
                  .each do |e|
                    resources << {
                      "uri"      => "textus://#{e.key.tr(".", "/")}",
                      "name"     => e.key,
                      "mimeType" => mime_for_format(e.format),
                    }
                  end
          end
          emit_result(rid, { "resources" => resources })
        end

        def handle_resources_read(rid, params)
          uri = params["uri"].to_s
          key = uri.delete_prefix("textus://").tr("/", ".")
          env = @store.as(@role).get(key)
          content = env.content || env.body || ""
          text = content.is_a?(Hash) ? JSON.dump(content) : content.to_s
          emit_result(rid, {
            "contents" => [{
              "uri"      => uri,
              "mimeType" => mime_for_format(@store.manifest.resolver.resolve(key).entry.format),
              "text"     => text,
            }],
          })
        rescue Textus::Error => e
          emit_error(rid, ToolError::JSONRPC_CODE, "resource read failed: #{e.message}")
        end

        def mime_for_format(format)
          case format.to_s
          when "json"  then "application/json"
          when "yaml"  then "application/yaml"
          else "text/plain"
          end
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
end
