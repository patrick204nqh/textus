module Textus
  class Manifest
    class Policy
      module Predicates
        class RawWriteOnce
          def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
            return { pass: true } if key.nil?

            path = manifest.resolver.resolve(key).path
            return { pass: true } unless File.exist?(path)

            { pass: false, error: Textus::Error.new(
              :raw_write_once,
              "raw entry '#{key}' already exists; " \
              "delete it first (`textus key-delete #{key}`), then re-ingest",
            ) }
          rescue Textus::UnknownKey
            { pass: true }
          end
        end
      end
    end
  end
end
