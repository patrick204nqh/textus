# frozen_string_literal: true

require "mcp"

module Textus
  module Surface
    module MCP
      # MCP stdio server backed by the official mcp gem. The SDK owns protocol
      # negotiation, tool dispatch, and JSON-RPC framing. This class owns the
      # textus Session lifecycle (built lazily on first tool call) and delegates
      # execution to Catalog.
      class Server
        def initialize(store:, role: Textus::Value::Role::DEFAULT, stdin: $stdin, stdout: $stdout)
          @store  = store
          @role   = role
          @stdin  = stdin
          @stdout = stdout
          # Session built eagerly so the contract_etag is captured at server start.
          # Changes to manifest/hooks/schemas after this point are detected as drift.
          @session = Textus::Store::Session.new(
            role: @role,
            cursor: @store.audit_log.latest_seq,
            propose_lane: @store.manifest.policy.propose_lane_for(@role),
            contract_etag: contract_etag_now,
          )

          @sdk = ::MCP::Server.new(
            name: "textus",
            version: Textus::VERSION,
            tools: Catalog.build_tools(self),
            resources: build_resources,
            server_context: { mcp_server: self },
          )
          @sdk.resources_read_handler { |params, server_context:| handle_resource_read(params[:uri].to_s, server_context) }
        end

        # Runs the stdio line loop; delegates each JSON line to the SDK.
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

        # Called from every MCP::Tool handler block in Catalog.
        # The SDK parses JSON with symbolize_names: true — all nested keys are symbols.
        # Deep-stringify so Catalog.call receives the string-key format it expects.
        def dispatch(verb_name, args, _server_context)
          str_args = deep_stringify_keys(args)
          @session.check_etag!(contract_etag_now) unless Catalog.read_verbs.include?(verb_name.to_s)
          result = Catalog.call(verb_name.to_s, session: @session, store: @store, args: str_args)
          update_session_for(verb_name.to_s)
          ::MCP::Tool::Response.new([{ type: "text", text: JSON.dump(result) }])
        rescue Textus::ContractDrift => e
          raise_handler_error(e.message, Textus::ContractDrift::JSONRPC_CODE)
        rescue CursorExpired => e
          raise_handler_error(e.message, CursorExpired::JSONRPC_CODE)
        rescue Textus::Surface::MCP::ToolError => e
          raise_handler_error(e.message, ToolError::JSONRPC_CODE)
        rescue StandardError => e
          raise_handler_error("internal: #{e.class}: #{e.message}", -32_603)
        end

        private

        def update_session_for(verb_name)
          @session = @session.advance_cursor(@store.audit_log.latest_seq) if verb_name == "pulse"
          @session = @session.with(contract_etag: contract_etag_now)      if verb_name == "boot"
        end

        def build_resources
          machine_lane = @store.manifest.policy.machine_lane
          return [] unless machine_lane

          @store.manifest.data.entries
                .select { |e| e.lane == machine_lane && e.is_a?(Textus::Manifest::Entry::Produced) }
                .map { |e| ::MCP::Resource.new(uri: "textus://#{e.key.tr(".", "/")}", name: e.key, mime_type: mime_for_format(e.format)) }
        end

        def handle_resource_read(uri, _server_context)
          key = uri.delete_prefix("textus://").tr("/", ".")
          env  = @store.as(@role).get(key)
          text = env.content.is_a?(Hash) ? JSON.dump(env.content) : (env.body || "").to_s
          mime = mime_for_format(@store.manifest.resolver.resolve(key).entry.format)
          [{ uri: uri, mimeType: mime, text: text }]
        rescue Textus::Error => e
          raise_handler_error("resource read failed: #{e.message}", -32_603)
        end

        def contract_etag_now = Textus::Value::Etag.for_contract(@store.root)

        # The SDK parses JSON with symbolize_names:true, making all nested hash keys symbols.
        # Recursively stringify so Catalog.call receives string-keyed hashes throughout.
        def deep_stringify_keys(obj)
          case obj
          when Hash  then obj.transform_keys(&:to_s).transform_values { |v| deep_stringify_keys(v) }
          when Array then obj.map { |v| deep_stringify_keys(v) }
          else obj
          end
        end

        def mime_for_format(format)
          case format.to_s
          when "json" then "application/json"
          when "yaml" then "application/yaml"
          else             "text/plain"
          end
        end

        def raise_handler_error(message, code)
          raise ::MCP::Server::RequestHandlerError.new(message, nil, error_code: code)
        end
      end
    end
  end
end
