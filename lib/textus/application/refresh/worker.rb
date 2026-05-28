require "timeout"

module Textus
  module Application
    module Refresh
      class Worker
        FETCH_TIMEOUT_SECONDS = 30

        def initialize(ctx:, ports:, envelope_io:, authorizer:, hook_context:)
          @ctx          = ctx
          @ports        = ports
          @manifest     = ports.manifest
          @envelope_io  = envelope_io
          @bus          = ports.event_bus
          @authorizer   = authorizer
          @hook_context = hook_context
        end

        def run(key)
          res = @manifest.resolver.resolve(key)
          mentry = res.entry
          path = res.path
          remaining = res.remaining
          raise UsageError.new("no intake declared for '#{key}'") unless mentry.is_a?(Textus::Manifest::Entry::Intake)

          before_etag = File.exist?(path) ? Etag.for_file(path) : nil
          result = fetch_with_bus(key, mentry, remaining)
          persist_and_notify(key, mentry, result, before_etag)
        end

        private

        def fetch_timeout_for(key)
          rule = @manifest.rules.for(key)
          rule&.refresh&.fetch_timeout_seconds || FETCH_TIMEOUT_SECONDS
        end

        def fetch_with_bus(key, mentry, remaining)
          callable = @bus.rpc_callable(:resolve_intake, mentry.handler)
          @bus.publish(:refresh_started, ctx: @hook_context, key: key, mode: :sync)
          call_intake(key, mentry, callable, remaining)
        end

        def call_intake(key, mentry, callable, remaining)
          timeout = fetch_timeout_for(key)
          Timeout.timeout(timeout) do
            kwargs = Textus::Hooks::Bus.inject_ports_kwargs(
              callable,
              ports: @ports,
              error_log: @bus.error_log,
              event: :resolve_intake,
              hook_name: mentry.handler,
              other: {
                config: mentry.config,
                args: { trigger_key: key, leaf_segments: remaining || [] },
              },
            )
            callable.call(**kwargs)
          end
        rescue Timeout::Error
          @bus.publish(:refresh_failed, ctx: @hook_context, key: key,
                                        error_class: "Timeout::Error",
                                        error_message: "intake '#{mentry.handler}' exceeded #{timeout}s")
          raise UsageError.new("intake '#{mentry.handler}' exceeded #{timeout}s timeout")
        rescue Textus::Error => e
          @bus.publish(:refresh_failed, ctx: @hook_context, key: key, error_class: e.class.name,
                                        error_message: e.message)
          raise
        rescue StandardError => e
          @bus.publish(:refresh_failed, ctx: @hook_context, key: key, error_class: e.class.name,
                                        error_message: e.message)
          raise UsageError.new("intake '#{mentry.handler}' raised: #{e.class}: #{e.message}")
        end

        def persist_and_notify(key, mentry, result, before_etag)
          normalized = self.class.send(:normalize_action_result, result, format: mentry.format)
          @authorizer.authorize_write!(mentry, role: @ctx.role)
          envelope = @envelope_io.write(
            key,
            mentry: mentry,
            payload: Textus::Application::Writes::EnvelopeIO::Payload.new(
              meta: normalized[:meta], body: normalized[:body], content: normalized[:content],
            ),
          )
          change = detect_change(before_etag, envelope)
          @bus.publish(:entry_refreshed, ctx: @hook_context, key: key, envelope: envelope, change: change) unless change == :unchanged
          envelope
        end

        def detect_change(before_etag, envelope)
          if before_etag.nil? then :created
          elsif envelope.etag == before_etag then :unchanged
          else :updated
          end
        end

        def self.normalize_action_result(res, format:)
          res = res.transform_keys(&:to_s) if res.is_a?(Hash)
          res ||= {}
          meta_val = res["_meta"]
          body     = res["body"]
          content  = res["content"]

          case format
          when "markdown" then { meta: meta_val || {}, body: body.to_s, content: nil }
          when "text"     then { meta: {}, body: body.to_s, content: nil }
          when "json", "yaml"
            if !content.nil?
              { meta: meta_val || {}, body: nil, content: content }
            elsif !body.nil?
              { meta: {}, body: body.to_s, content: nil }
            else
              raise Textus::UsageError.new("intake for #{format} returned neither content nor body")
            end
          else
            raise Textus::UsageError.new("unknown format #{format.inspect}")
          end
        end
        private_class_method :normalize_action_result
      end
    end
  end
end
