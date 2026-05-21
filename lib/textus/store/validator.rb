module Textus
  class Store
    class Validator
      def initialize(store)
        @store = store
      end

      def call
        violations = []
        @store.manifest.enumerate.each do |row|
          begin
            @store.get(row[:key])
          rescue Textus::Error => e
            violations << { "key" => row[:key], "code" => e.code, "message" => e.message }
          end
        end

        @store.manifest.enumerate.each do |row|
          mentry = row[:manifest_entry]
          next unless mentry.schema

          schema = @store.schema_for(mentry.schema)
          next unless schema

          env = begin
            @store.get(row[:key])
          rescue StandardError
            next
          end
          last_writer = @store.audit_log.last_writer_for(row[:key])
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
