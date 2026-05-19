module Textus
  module Hooks
    EVENTS = %w[on_put on_delete on_refresh on_stale on_accept on_build].freeze

    def self.list(manifest, event: nil)
      raise UsageError.new("unknown event: #{event}") if event && !EVENTS.include?(event)

      rows = []
      manifest.entries.each do |e|
        e.events.each do |evt, defs|
          next if event && evt != event

          Array(defs).each do |defn|
            rows << {
              "key" => e.key,
              "event" => evt,
              "run" => defn["run"],
              "as" => defn["as"] || "script",
            }
          end
        end
      end
      rows
    end
  end
end
