require "json"
require_relative "routing"

module Textus
  module Surfaces
    module MCP
      # Stdio JSON-RPC 2.0 server speaking MCP draft 2024-11-05. One line per
      # message (NDJSON). Holds a single Session for the lifetime of stdin.
      class Server
        include Routing

        PROTOCOL_VERSION = "2024-11-05"
        SERVER_INFO      = { "name" => "textus", "version" => Textus::VERSION }.freeze
        MAX_LINE_BYTES   = 1_048_576 # 1 MB — protects against OOM from oversized tool calls

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
          return reject_oversized(line) if line.bytesize > MAX_LINE_BYTES

          parse_and_dispatch(line)
        end

        def reject_oversized(line)
          emit_error(nil, -32_700, "message too large (#{line.bytesize} bytes, limit #{MAX_LINE_BYTES})")
        end

        def parse_and_dispatch(line)
          dispatch(JSON.parse(line))
        rescue JSON::ParserError => e
          emit_error(nil, -32_700, "parse error: #{e.message}")
        end

        def handle_initialize(rid, _params)
          @session = build_session
          emit_result(rid, {
                        "protocolVersion" => PROTOCOL_VERSION,
                        "serverInfo" => SERVER_INFO,
                        "capabilities" => { "tools" => {}, "resources" => {} },
                      })
        end

        def build_session
          # The acting role IS the resolved connection role (ADR 0040): the MCP
          # transport defaults to `agent`, which can write the queue, so its
          # propose_lane resolves directly. If a connection's role cannot propose,
          # propose_lane is nil and the `propose` tool reports that honestly.
          Session.new(
            role: @role,
            cursor: @store.audit_log.latest_seq,
            propose_lane: @store.manifest.policy.propose_lane_for(@role),
            contract_etag: contract_etag,
          )
        end

        def handle_tools_list(rid)
          emit_result(rid, { "tools" => Catalog.tool_schemas })
        end

        def handle_tools_call(rid, params)
          return unless session_ready?(rid)

          invoke_tool(rid, params["name"], params["arguments"] || {})
        rescue Textus::ContractDrift, CursorExpired, ToolError => e
          emit_error(rid, e.class::JSONRPC_CODE, e.message)
        rescue StandardError => e
          emit_error(rid, -32_603, "internal: #{e.class}: #{e.message}")
        end

        def session_ready?(rid)
          return true if @session

          emit_error(rid, -32_002, "session not initialized; call 'initialize' first")
          false
        end

        def invoke_tool(rid, name, args)
          # ADR 0083: contract-drift guard gates mutating verbs only
          @session.check_etag!(contract_etag) unless Catalog.read_verbs.include?(name)
          result = Catalog.call(name, session: @session, store: @store, args: args)
          update_session_for(name)
          emit_tool_result(rid, result)
        end

        def update_session_for(name)
          @session = @session.advance_cursor(@store.audit_log.latest_seq) if name == "pulse"
          @session = @session.with(contract_etag: contract_etag) if name == "boot"
        end

        def emit_tool_result(rid, result)
          emit_result(rid, {
                        "content" => [{ "type" => "text", "text" => JSON.dump(result) }],
                        "isError" => false,
                      })
        end

        def handle_resources_list(rid)
          emit_result(rid, { "resources" => machine_resources })
        end

        def machine_resources
          machine_lane = @store.manifest.policy.machine_lane
          return [] unless machine_lane

          produced_entries(machine_lane).map { |e| resource_descriptor(e) }
        end

        def produced_entries(machine_lane)
          @store.manifest.data.entries
                .select { |e| e.lane == machine_lane && e.is_a?(Textus::Manifest::Entry::Produced) }
        end

        def resource_descriptor(entry)
          {
            "uri" => "textus://#{entry.key.tr(".", "/")}",
            "name" => entry.key,
            "mimeType" => mime_for_format(entry.format),
          }
        end

        def handle_resources_read(rid, params)
          uri = params["uri"].to_s
          key = uri.delete_prefix("textus://").tr("/", ".")
          emit_result(rid, resource_contents(uri, key))
        rescue Textus::Error => e
          emit_error(rid, ToolError::JSONRPC_CODE, "resource read failed: #{e.message}")
        end

        def resource_contents(uri, key)
          env  = @store.as(@role).get(key)
          text = resource_text(env.content || env.body || "")
          mime = mime_for_format(@store.manifest.resolver.resolve(key).entry.format)
          { "contents" => [{ "uri" => uri, "mimeType" => mime, "text" => text }] }
        end

        def resource_text(content)
          content.is_a?(Hash) ? JSON.dump(content) : content.to_s
        end

        def contract_etag
          Textus::Etag.for_contract(@store.root)
        end

        def mime_for_format(format)
          case format.to_s
          when "json" then "application/json"
          when "yaml" then "application/yaml"
          else             "text/plain"
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
