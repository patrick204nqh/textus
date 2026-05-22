require "timeout"

module Textus
  module Application
    module Refresh
      class Worker
        FETCH_TIMEOUT_SECONDS = 30

        def initialize(store:, bus:)
          @store = store
          @bus = bus
        end

        def run(key, as:)
          mentry, path, = @store.manifest.resolve(key)
          raise UsageError.new("no intake declared for '#{key}'") unless mentry.intake_handler

          before_etag = File.exist?(path) ? Etag.for_file(path) : nil
          result = fetch_with_bus(key, mentry, as)
          persist_and_notify(key, mentry, result, before_etag, as)
        end

        private

        def store_view(writable: false, as: nil)
          Store::View.new(@store, writable: writable, as: as)
        end

        def fetch_with_bus(key, mentry, as)
          callable = @store.registry.rpc_callable(:intake, mentry.intake_handler)
          write_view = store_view(writable: true, as: as)
          read_view  = store_view
          @bus.publish(:refresh_started, store: read_view, key: key, mode: :sync)
          call_intake(key, mentry, callable, write_view, read_view)
        end

        def call_intake(key, mentry, callable, write_view, read_view)
          Timeout.timeout(FETCH_TIMEOUT_SECONDS) do
            callable.call(store: write_view, config: mentry.intake_config, args: {})
          end
        rescue Timeout::Error
          @bus.publish(:refresh_failed, store: read_view, key: key, error_class: "Timeout::Error",
                                        error_message: "intake '#{mentry.intake_handler}' exceeded #{FETCH_TIMEOUT_SECONDS}s")
          raise UsageError.new("intake '#{mentry.intake_handler}' exceeded #{FETCH_TIMEOUT_SECONDS}s timeout")
        rescue Textus::Error => e
          @bus.publish(:refresh_failed, store: read_view, key: key, error_class: e.class.name, error_message: e.message)
          raise
        rescue StandardError => e
          @bus.publish(:refresh_failed, store: read_view, key: key, error_class: e.class.name, error_message: e.message)
          raise UsageError.new("intake '#{mentry.intake_handler}' raised: #{e.class}: #{e.message}")
        end

        def persist_and_notify(key, mentry, result, before_etag, as)
          normalized = Textus::Refresh.normalize_action_result(result, format: mentry.format)
          envelope = @store.put(
            key,
            meta: normalized[:meta], body: normalized[:body], content: normalized[:content],
            as: as, suppress_events: true
          )
          change = detect_change(before_etag, envelope)
          read_view = store_view
          @bus.publish(:refreshed, store: read_view, key: key, envelope: envelope, change: change) unless change == :unchanged
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
