module Textus
  module Application
    module Refresh
      module All
        module_function

        def call(store, prefix: nil, zone: nil, as: "script")
          bus = Textus::Infra::EventBus.new(registry: store.registry)
          worker = Textus::Application::Refresh::Worker.new(store: store, bus: bus)

          stale_rows = store.stale(prefix: prefix, zone: zone)
          refreshed = []
          failed = []
          skipped = []

          stale_rows.each do |row|
            key = row["key"] || row[:key]
            reason = row["reason"] || row[:reason]
            if reason.to_s.match?(/ttl exceeded|never refreshed/)
              begin
                worker.run(key, as: as)
                refreshed << key
              rescue Textus::Error => e
                failed << { "key" => key, "error" => e.message }
              end
            else
              skipped << { "key" => key, "reason" => reason }
            end
          end

          {
            "protocol" => Textus::PROTOCOL,
            "ok" => failed.empty?,
            "refreshed" => refreshed,
            "failed" => failed,
            "skipped" => skipped,
          }
        end
      end
    end
  end
end
