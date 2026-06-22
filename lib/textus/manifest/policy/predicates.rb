module Textus
  class Manifest
    class Policy
      module Predicates
        FLOOR = {
          put: %w[lane_writable_by raw_lane_ingest_only],
          key_delete: %w[lane_deletable_by],
          key_mv: %w[lane_writable_by raw_lane_ingest_only],
          accept: %w[author_held],
          reject: %w[author_held],
          propose: %w[lane_writable_by raw_lane_ingest_only],
          key_mv_prefix: %w[lane_writable_by raw_lane_ingest_only],
          key_delete_prefix: %w[lane_writable_by raw_lane_ingest_only],
          ingest: %w[lane_writable_by raw_write_once],
        }.freeze

        CLASSES = {
          "lane_writable_by" => "LaneWritableBy",
          "author_held" => "AuthorHeld",
          "target_is_canon" => "TargetIsCanon",
          "etag_match" => "EtagMatch",
          "schema_valid" => "SchemaValid",
          "fresh_within" => "FreshWithin",
          "raw_lane_ingest_only" => "RawLaneIngestOnly",
          "raw_write_once" => "RawWriteOnce",
          "lane_deletable_by" => "LaneDeletableBy",
        }.freeze

        module_function

        def by_name(name)
          short = CLASSES.fetch(name.to_s) do
            raise Textus::UsageError.new("unknown predicate '#{name}'")
          end
          const_get(short)
        end

        def evaluate(manifest:, action:, actor:, key:, schemas: nil, envelope: nil, extra: {}, rule_predicates: [])
          failures = []
          (FLOOR.fetch(action, []) + rule_predicates).uniq.each do |pred_name|
            result = by_name(pred_name).call(
              manifest:, schemas:, actor:, action:, key:, envelope:, extra:,
            )
            next if result[:pass]
            raise result[:error] if result[:error]

            failures << [pred_name, result[:reason]]
          end
          raise Textus::GuardFailed.new(failures) unless failures.empty?
        end
      end
    end
  end
end
