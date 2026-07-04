# frozen_string_literal: true

require "mcp"

module Textus
  module Surface
    module MCP
      class Server
        CHECKPOINT_INTERVAL = 30
        MCP_ADAPTER = Textus::Surface::MCP::Adapters::McpAdapter.new

        def initialize(store:, role: Textus::Value::Role::DEFAULT, stdin: $stdin, stdout: $stdout)
          @store  = store.with_role(role)
          @stdin  = stdin
          @stdout = stdout
          @shutdown = false

          resume_from_cursor!
          start_cursor_checkpoint_thread!

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
          str_args = deep_stringify_keys(args)

          is_read = Catalog.read_verbs.include?(verb_name.to_s)
          previous_etag = @store.contract_etag
          current_etag = contract_etag_now
          drifted = current_etag != previous_etag

          result = Catalog.call(verb_name.to_s, store: @store, args: str_args)
          result = DriftAnnotation.apply(
            result, verb_name:, drifted:, is_read:,
                    current_etag: short_etag(current_etag),
                    previous_etag: short_etag(previous_etag)
          )

          @store = @store.advance_cursor(@store.container.store.event_store.latest_seq) if verb_name == :pulse
          @store = @store.with_role(@store.role) if verb_name == :boot
          ::MCP::Tool::Response.new([{ type: "text", text: JSON.dump(result) }])
        rescue Textus::CursorExpired => e
          raise_handler_error(e.message, Textus::CursorExpired::JSONRPC_CODE)
        rescue Textus::Surface::MCP::ToolError => e
          raise_handler_error(e.message, ToolError::JSONRPC_CODE)
        rescue StandardError => e
          raise_handler_error("internal: #{e.message}", -32_603)
        end

        private

        def resume_from_cursor!
          saved = @store.container.store.cursor_store.read(@store.role)
          latest = @store.container.store.event_store.latest_seq
          @store = @store.advance_cursor(saved) if saved.positive? && saved <= latest
        end

        def start_cursor_checkpoint_thread!
          @checkpoint_thread = Thread.new do
            loop do
              sleep(self.class::CHECKPOINT_INTERVAL)
              break if @shutdown

              @store.container.store.cursor_store.write(@store.role, @store.cursor)
            end
          end
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
