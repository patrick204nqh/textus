module Textus
  class Store
    class Validator
      def initialize(reader:, manifest:, audit_log:, schema_for:)
        @reader = reader
        @manifest = manifest
        @audit_log = audit_log
        @schema_for = schema_for
      end

      def call
        violations = []
        @manifest.enumerate.each do |row|
          begin
            @reader.get(row[:key])
          rescue Textus::Error => e
            violations << { "key" => row[:key], "code" => e.code, "message" => e.message }
          end
        end

        @manifest.enumerate.each do |row|
          mentry = row[:manifest_entry]
          next unless mentry.schema

          schema = @schema_for.call(mentry.schema)
          next unless schema

          env = begin
            @reader.get(row[:key])
          rescue StandardError
            next
          end
          last_writer = @audit_log.last_writer_for(row[:key])
          next if last_writer.nil?

          env["_meta"].each_key do |field|
            owner = schema.maintained_by(field)
            next if owner.nil?
            next if last_writer == owner
            next if last_writer == "human"

            violations << {
              "key" => row[:key],
              "code" => "role_authority",
              "field" => field,
              "expected" => owner,
              "last_writer" => last_writer,
            }
          end
        end

        { "protocol" => PROTOCOL, "ok" => violations.empty?, "violations" => violations }
      end
    end
  end
end
