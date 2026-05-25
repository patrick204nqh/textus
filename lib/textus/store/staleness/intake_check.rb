require "time"

module Textus
  class Store
    class Staleness
      # Reports TTL-exceeded staleness for intake-handler entries. Returns an
      # Array of row hashes (possibly empty) per entry.
      class IntakeCheck
        def initialize(manifest:)
          @manifest = manifest
        end

        def rows_for(mentry)
          return [] unless mentry.intake_handler

          ttl = @manifest.policies_for(mentry.key).refresh&.ttl_seconds
          return [] unless ttl

          path = Textus::Key::Path.resolve(@manifest, mentry)
          return [row(mentry, path, "never refreshed")] unless File.exist?(path)

          meta = Entry.for_format(mentry.format).parse(File.binread(path), path: path)["_meta"]
          last_str = meta["last_refreshed_at"]
          return [row(mentry, path, "never refreshed (no last_refreshed_at)")] if last_str.nil?

          last = parse_time(last_str)
          return [row(mentry, path, "ttl exceeded (#{ttl}s)")] if last.nil? || (Time.now - last) > ttl

          []
        end

        private

        def parse_time(str)
          Time.parse(str.to_s)
        rescue StandardError
          nil
        end

        def row(mentry, path, reason)
          { "key" => mentry.key, "path" => path, "handler" => mentry.intake_handler, "reason" => reason }
        end
      end
    end
  end
end
