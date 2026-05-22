require "timeout"

module Textus
  module Application
    module Refresh
      class Worker
        FETCH_TIMEOUT_SECONDS = 30

        def initialize(ctx:, bus:)
          @ctx = ctx
          @bus = bus
        end

        def run(key)
          mentry, path, = @ctx.store.manifest.resolve(key)
          raise UsageError.new("no intake declared for '#{key}'") unless mentry.intake_handler

          before_etag = File.exist?(path) ? Etag.for_file(path) : nil
          result = fetch_with_bus(key, mentry)
          persist_and_notify(key, mentry, result, before_etag)
        end

        private

        def read_view
          Application::Context.new(store: @ctx.store, role: @ctx.role)
        end

        def fetch_with_bus(key, mentry)
          callable = @ctx.store.registry.rpc_callable(:intake, mentry.intake_handler)
          @bus.publish(:refresh_began, store: read_view, key: key, mode: :sync,
                                       correlation_id: @ctx.correlation_id)
          call_intake(key, mentry, callable)
        end

        def call_intake(key, mentry, callable)
          Timeout.timeout(FETCH_TIMEOUT_SECONDS) do
            callable.call(store: @ctx, config: mentry.intake_config, args: {})
          end
        rescue Timeout::Error
          @bus.publish(:refresh_failed, store: read_view, key: key, error_class: "Timeout::Error",
                                        error_message: "intake '#{mentry.intake_handler}' exceeded #{FETCH_TIMEOUT_SECONDS}s",
                                        correlation_id: @ctx.correlation_id)
          raise UsageError.new("intake '#{mentry.intake_handler}' exceeded #{FETCH_TIMEOUT_SECONDS}s timeout")
        rescue Textus::Error => e
          @bus.publish(:refresh_failed, store: read_view, key: key, error_class: e.class.name,
                                        error_message: e.message, correlation_id: @ctx.correlation_id)
          raise
        rescue StandardError => e
          @bus.publish(:refresh_failed, store: read_view, key: key, error_class: e.class.name,
                                        error_message: e.message, correlation_id: @ctx.correlation_id)
          raise UsageError.new("intake '#{mentry.intake_handler}' raised: #{e.class}: #{e.message}")
        end

        def persist_and_notify(key, mentry, result, before_etag)
          normalized = Textus::Refresh.normalize_action_result(result, format: mentry.format)
          envelope = @ctx.store.put(
            key,
            meta: normalized[:meta], body: normalized[:body], content: normalized[:content],
            as: @ctx.role, suppress_events: true
          )
          change = detect_change(before_etag, envelope)
          unless change == :unchanged
            @bus.publish(:refreshed, store: read_view, key: key, envelope: envelope, change: change,
                                     correlation_id: @ctx.correlation_id)
          end
          envelope
        end

        def detect_change(before_etag, envelope)
          if before_etag.nil? then :created
          elsif envelope["etag"] == before_etag then :unchanged
          else :updated
          end
        end
      end
    end
  end
end
