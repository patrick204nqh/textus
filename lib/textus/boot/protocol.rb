module Textus
  module Boot
    module Protocol
      ENVELOPE_SHAPE = {
        "envelope_shape" => {
          "summary" => "every read/write payload is a JSON envelope with _meta, body, uid, and etag",
          "fields" => {
            "_meta" => "hash of structured frontmatter; schema-validated per entry family",
            "body"  => "string payload (markdown/text) or nil for json/yaml formats",
            "uid"   => "stable 16-char hex identifier; preserved across writes and key renames",
            "etag"  => "content hash; pass back on writes to detect concurrent edits",
          },
        },
      }.freeze

      def self.build(manifest)
        ENVELOPE_SHAPE.merge(
          "lanes" => lanes_for(manifest),
          "roles" => Textus::Protocol::V4::LANES.values.flat_map { |r| r[:writers] }.uniq,
        )
      end

      def self.lanes_for(manifest)
        manifest.data.declared_lane_kinds.keys.map do |name|
          row = { "name" => name, "writers" => manifest.policy.writers_for(name) }
          purpose = manifest.data.lane_descs[name]
          row["purpose"] = purpose if purpose && !purpose.empty?
          row
        end
      end
    end
  end
end
