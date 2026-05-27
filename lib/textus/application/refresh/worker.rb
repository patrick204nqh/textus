require "timeout"

module Textus
  module Application
    module Refresh
      class Worker
        FETCH_TIMEOUT_SECONDS = 30

        def initialize(ctx:, envelope_io:)
          @ctx = ctx
          @envelope_io = envelope_io
        end

        def run(key)
          res = @ctx.store.manifest.resolve(key)
          mentry = res.entry
          path = res.path
          remaining = res.remaining
          raise UsageError.new("no intake declared for '#{key}'") unless mentry.intake_handler

          before_etag = File.exist?(path) ? Etag.for_file(path) : nil
          result = fetch_with_bus(key, mentry, remaining)
          persist_and_notify(key, mentry, result, before_etag)
        end

        private

        def read_view
          Application::Context.legacy(store: @ctx.store, role: @ctx.role)
        end

        def fetch_timeout_for(key)
          rule = @ctx.store.manifest.rules_for(key)
          rule&.refresh&.fetch_timeout_seconds || FETCH_TIMEOUT_SECONDS
        end

        def fetch_with_bus(key, mentry, remaining)
          callable = @ctx.store.registry.rpc_callable(:resolve_intake, mentry.intake_handler)
          @ctx.bus.publish(:refresh_started, store: read_view, key: key, mode: :sync,
                                             correlation_id: @ctx.correlation_id)
          call_intake(key, mentry, callable, remaining)
        end

        def call_intake(key, mentry, callable, remaining)
          timeout = fetch_timeout_for(key)
          Timeout.timeout(timeout) do
            callable.call(
              store: @ctx,
              config: mentry.intake_config,
              args: { trigger_key: key, leaf_segments: remaining || [] },
            )
          end
        rescue Timeout::Error
          @ctx.bus.publish(:refresh_failed, store: read_view, key: key, error_class: "Timeout::Error",
                                            error_message: "intake '#{mentry.intake_handler}' exceeded #{timeout}s",
                                            correlation_id: @ctx.correlation_id)
          raise UsageError.new("intake '#{mentry.intake_handler}' exceeded #{timeout}s timeout")
        rescue Textus::Error => e
          @ctx.bus.publish(:refresh_failed, store: read_view, key: key, error_class: e.class.name,
                                            error_message: e.message, correlation_id: @ctx.correlation_id)
          raise
        rescue StandardError => e
          @ctx.bus.publish(:refresh_failed, store: read_view, key: key, error_class: e.class.name,
                                            error_message: e.message, correlation_id: @ctx.correlation_id)
          raise UsageError.new("intake '#{mentry.intake_handler}' raised: #{e.class}: #{e.message}")
        end

        def persist_and_notify(key, mentry, result, before_etag)
          normalized = Textus::Refresh.normalize_action_result(result, format: mentry.format)
          envelope = Textus::Application::Writes::Put.new(ctx: @ctx, envelope_io: @envelope_io).call(
            key,
            meta: normalized[:meta], body: normalized[:body], content: normalized[:content],
            suppress_events: true
          )
          change = detect_change(before_etag, envelope)
          unless change == :unchanged
            @ctx.bus.publish(:entry_refreshed, store: read_view, key: key, envelope: envelope, change: change,
                                               correlation_id: @ctx.correlation_id)
          end
          envelope
        end

        def detect_change(before_etag, envelope)
          if before_etag.nil? then :created
          elsif envelope.etag == before_etag then :unchanged
          else :updated
          end
        end
      end
    end
  end
end
