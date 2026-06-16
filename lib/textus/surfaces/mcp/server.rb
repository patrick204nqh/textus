# frozen_string_literal: true

require "mcp"

module Textus
  module Surfaces
    module MCP
      # MCP stdio server backed by the official mcp gem. The SDK owns protocol
      # negotiation, tool dispatch, and JSON-RPC framing. This class owns the
      # textus Session lifecycle (built lazily on first tool call) and delegates
      # execution to Catalog.
      class Server
        def initialize(store:, role: Textus::Role::DEFAULT, stdin: $stdin, stdout: $stdout)
          @store   = store
          @role    = role
          @stdin   = stdin
          @stdout  = stdout
          @session = nil

          @sdk = ::MCP::Server.new(
            name: "textus",
            version: Textus::VERSION,
            tools: Catalog.build_tools(self),
            server_context: { mcp_server: self },
          )
          @sdk.resources_list_handler  { |server_context:| list_resources(server_context) }
          @sdk.resources_read_handler  { |params, server_context:| handle_resource_read(params[:uri].to_s, server_context) }
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
        def dispatch(verb_name, args, _server_context)
          ensure_session!
          @session.check_etag!(contract_etag) unless Catalog.read_verbs.include?(verb_name.to_s)
          result = Catalog.call(verb_name.to_s, session: @session, store: @store, args: args)
          update_session_for(verb_name.to_s)
          ::MCP::Tool::Response.new([{ type: "text", text: JSON.dump(result) }])
        rescue Textus::ContractDrift => e
          raise_handler_error(e.message, Textus::ContractDrift::JSONRPC_CODE)
        rescue CursorExpired => e
          raise_handler_error(e.message, CursorExpired::JSONRPC_CODE)
        rescue Textus::Surfaces::MCP::ToolError => e
          raise_handler_error(e.message, ToolError::JSONRPC_CODE)
        rescue StandardError => e
          raise_handler_error("internal: #{e.class}: #{e.message}", -32_603)
        end

        private

        def ensure_session!
          return if @session

          @session = Textus::Session.new(
            role: @role,
            cursor: @store.audit_log.latest_seq,
            propose_lane: @store.manifest.policy.propose_lane_for(@role),
            contract_etag: contract_etag,
          )
        end

        def update_session_for(verb_name)
          @session = @session.advance_cursor(@store.audit_log.latest_seq) if verb_name == "pulse"
          @session = @session.with(contract_etag: contract_etag)          if verb_name == "boot"
        end

        def list_resources(_server_context)
          machine_lane = @store.manifest.policy.machine_lane
          return [] unless machine_lane

          @store.manifest.data.entries
                .select { |e| e.lane == machine_lane && e.is_a?(Textus::Manifest::Entry::Produced) }
                .map { |e| resource_descriptor(e) }
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

        def resource_descriptor(entry)
          { uri: "textus://#{entry.key.tr(".", "/")}", name: entry.key, mimeType: mime_for_format(entry.format) }
        end

        def contract_etag = Textus::Etag.for_contract(@store.root)

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
