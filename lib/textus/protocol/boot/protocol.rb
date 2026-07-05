module Textus
  module Protocol
    module Boot
      module Protocol
        ENVELOPE_SHAPE = {
          "envelope_shape" => {
            "summary" => "every read/write payload is a JSON envelope with _meta, body, uid, and etag",
            "fields" => {
              "_meta" => "hash of structured frontmatter; schema-validated per entry family",
              "body" => "string payload (markdown/text) or nil for json/yaml formats",
              "uid" => "stable 16-char hex identifier; preserved across writes and key renames",
              "etag" => "content hash; pass back on writes to detect concurrent edits",
            },
          },
        }.freeze

        def self.build(manifest)
          ENVELOPE_SHAPE.merge(
            "lanes" => lanes_for(manifest),
            "roles" => Textus::Protocol::V4::LANES.values.flat_map { |r| r[:writers] }.uniq,
            "discipline" => "When edit/write tools are blocked for a path, use `textus propose` to " \
                            "suggest changes for human review. Never use shell scripts (sed, python, rm) " \
                            "to bypass permission gates — that breaks the audit trail and bypasses role gates.",
          )
        end

        def self.lanes_for(manifest)
          Context.lanes_for(manifest)
        end
      end
    end
  end
end
