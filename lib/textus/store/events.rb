require "timeout"

module Textus
  class Store
    class Events
      HOOK_TIMEOUT_SECONDS = 2

      def initialize(store)
        @store = store
      end

      def call(event, **kwargs)
        view = StoreView.new(@store)
        @store.registry.hooks(event).each do |entry|
          name = entry[:name]
          Timeout.timeout(HOOK_TIMEOUT_SECONDS) { entry[:callable].call(store: view, **kwargs) }
        rescue StandardError => e
          extras = { "event" => event.to_s, "hook" => name.to_s, "error" => "#{e.class}: #{e.message}" }
          extras["target_key"]  = kwargs[:target_key]  if kwargs.key?(:target_key)
          extras["pending_key"] = kwargs[:pending_key] if kwargs.key?(:pending_key)
          @store.audit_log.append(
            role: "script", verb: "event_error",
            key: kwargs[:key] || kwargs[:target_key] || kwargs[:pending_key] || "-",
            etag_before: nil, etag_after: nil,
            extras: extras
          )
        end
      end
    end
  end
end
