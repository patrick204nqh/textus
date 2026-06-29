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
          @store  = store.with_role(role)
          @stdin  = stdin
          @stdout = stdout

          @sdk = ::MCP::Server.new(
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
          str_args = deep_stringify_keys(args)
          @store.check_etag!(contract_etag_now) unless Catalog.read_verbs.include?(verb_name.to_s)
          result = Catalog.call(verb_name.to_s, store: @store, args: str_args)
          @store = @store.advance_cursor(@store.audit_log.latest_seq) if verb_name == :pulse
          @store = @store.with_role(@store.role) if verb_name == :boot
          ::MCP::Tool::Response.new([{ type: "text", text: JSON.dump(result) }])
        rescue Textus::ContractDrift => e
          raise_handler_error(e.message, Textus::ContractDrift::JSONRPC_CODE)
        rescue Textus::CursorExpired => e
          raise_handler_error(e.message, Textus::CursorExpired::JSONRPC_CODE)
        rescue Textus::Surface::MCP::ToolError => e
          raise_handler_error(e.message, ToolError::JSONRPC_CODE)
        rescue StandardError => e
          raise_handler_error("internal: #{e.message}", -32_603)
        end

        private

        # Snapshot at server init against the boot-time manifest. New produced entries
        # added by a later reconcile are invisible until the server restarts — this is
        # intentional: a ContractDrift will gate writes on any mid-session manifest change.
        def build_resources
          machine_lane = @store.manifest.policy.machine_lane
          return [] unless machine_lane

          @store.manifest.data.entries
                .select { |e| e.lane == machine_lane && e.is_a?(Textus::Manifest::Entry::Produced) }
                .map { |e| ::MCP::Resource.new(uri: "textus://#{e.key.tr(".", "/")}", name: e.key, mime_type: mime_for_format(e.format)) }
        end

        def handle_resource_read(uri, _server_context)
          key  = uri.delete_prefix("textus://").tr("/", ".")
          env  = @store.get(key:)
          text = env.content.is_a?(Hash) ? JSON.dump(env.content) : (env.body || "").to_s
          mime = mime_for_format(env.format)
          [{ uri: uri, mimeType: mime, text: text }]
        rescue Textus::Error => e
          raise_handler_error("resource read failed: #{e.message}", -32_603)
        rescue StandardError => e
          raise_handler_error("internal: #{e.message}", -32_603)
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
