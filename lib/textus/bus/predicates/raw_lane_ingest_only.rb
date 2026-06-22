module Textus
  module Bus
    module Predicates
      class RawLaneIngestOnly
        def self.call(manifest:, schemas: nil, actor:, action:, key:, envelope: nil, extra: {})
          return { pass: true } if key.nil?

          mentry = manifest.resolver.resolve(key).entry
          return { pass: true } unless manifest.policy.declared_kind(mentry.lane.to_s) == :raw
          return { pass: true } if action == :ingest

          { pass: false, error: Textus::Error.new(
            :raw_lane_ingest_only,
            "raw lane '#{mentry.lane}' only accepts `textus ingest` — " \
            "use that verb instead of '#{action}'",
          ) }
        rescue Textus::UnknownKey
          { pass: true }
        end
      end
    end
  end
end
