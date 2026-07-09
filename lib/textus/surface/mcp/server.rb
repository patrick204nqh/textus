require "mcp"

module Textus
  module Surface
    module MCP
      class Server
        CHECKPOINT_INTERVAL = 30
        MCP_ADAPTER = Textus::Surface::MCP::Adapters::McpAdapter.new
        GATE_ADAPTER = Textus::Adapters::McpAdapter.new

        def initialize(store:, role: Textus::Value::Role::DEFAULT, stdin: $stdin, stdout: $stdout)
          @store  = store.with_role(role)
          @gate   = @store.gate
          @stdin  = stdin
          @stdout = stdout
          @shutdown = false
          @cursor_manager = CursorManager.new(store: @store, role:)

          @store = @cursor_manager.resume! || @store

          @sdk = MCP_ADAPTER.server(
            name: "textus",
            version: Textus::VERSION,
            tools: Catalog.build_tools(self),
            resources: build_resources,
            server_context: { mcp_server: self },
          )
          @sdk.resources_read_handler { |params, server_context:| handle_resource_read(params[:uri].to_s, server_context) }
        end

        def run
          @stdin.each_line do |line|
            line = line.strip
            next if line.empty?

            response = @sdk.handle_json(line)
            next unless response

            @stdout.puts(response)
            @stdout.flush
          end
        end

        def dispatch(verb_name, args, _server_context)
          drifted = drift_detected?
          response = GATE_ADAPTER.call(verb_name, params: args, gate: @gate, role: @store.role)
          raise response.error if response.error

          result = response.payload
          result = DriftAnnotation.apply(
            result, verb_name:, drifted:, is_read: Catalog.read_verbs.include?(verb_name.to_s),
                    current_etag: short_etag(contract_etag_now),
                    previous_etag: short_etag(@store.contract_etag)
          )

          post_dispatch!(verb_name)
          ::MCP::Tool::Response.new([{ type: "text", text: JSON.dump(result) }])
        rescue Textus::CursorExpired => e
          raise_handler_error(e.message, Textus::CursorExpired::JSONRPC_CODE)
        rescue Textus::Surface::MCP::ToolError => e
          raise_handler_error(e.message, ToolError::JSONRPC_CODE)
        rescue Textus::Error => e
          raise_handler_error(e.message, -32_603)
        rescue StandardError => e
          raise_handler_error("internal: #{e.message}", -32_603)
        end

        private

        def drift_detected?
          @store.contract_etag != contract_etag_now
        end

        def post_dispatch!(verb_name)
          @store = @cursor_manager.advance!(seq: @store.container.store.audit_log.latest[:seq]) if verb_name == :pulse
          @store = @store.with_role(@store.role) if verb_name == :boot
        end

        def build_resources
          machine_lane = @store.respond_to?(:container) ? @store.container.manifest.policy.machine_lane : nil
          return [] unless machine_lane

          entries = @store.respond_to?(:container) ? @store.container.manifest.data.entries : []
          entries.select { |e| e.lane == machine_lane }
                 .map { |e| ::MCP::Resource.new(uri: "textus://#{e.key.tr(".", "/")}", name: e.key, mime_type: mime_for_format(e.format)) }
        end

        def handle_resource_read(uri, _server_context)
          key  = uri.delete_prefix("textus://").tr("/", ".")
          env  = @store.get(key:)
          text = env["content"].is_a?(Hash) ? JSON.dump(env["content"]) : (env["body"] || "").to_s
          mime = mime_for_format(env["format"])
          [{ uri: uri, mimeType: mime, text: text }]
        rescue Textus::Error => e
          raise_handler_error("resource read failed: #{e.message}", -32_603)
        rescue StandardError => e
          raise_handler_error("internal: #{e.message}", -32_603)
        end

        def contract_etag_now = Textus::Value::Etag.for_contract(@store.layout)

        def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]

        def mime_for_format(format)
          case format.to_s
          when "json"     then "application/json"
          when "yaml"     then "application/yaml"
          when "markdown" then "text/markdown"
          else                 "text/plain"
          end
        end

        def raise_handler_error(message, code)
          raise ::MCP::Server::RequestHandlerError.new(message, nil, error_code: code)
        end
      end
    end
  end
end
