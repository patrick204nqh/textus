module Textus
  module Domain
    # Reports leaves whose age (now - file mtime) exceeds a retention window.
    # Each row is { "key", "path", "action" => "expire"|"archive", "age_seconds" }.
    class Retention
      def initialize(manifest:, file_stat:, clock:)
        @manifest  = manifest
        @file_stat = file_stat
        @clock     = clock
      end

      def call(prefix: nil, zone: nil)
        @manifest.data.entries
                 .select { |m| entry_matches?(m, prefix: prefix, zone: zone) }
                 .flat_map { |m| rows_for(m) }
      end

      private

      def rows_for(mentry)
        policy = @manifest.rules.for(mentry.key).retention
        return [] if policy.nil?

        @manifest.resolver.enumerate(prefix: mentry.key).filter_map do |row|
          path = row[:path]
          next unless @file_stat.exists?(path)

          age = (@clock.now - @file_stat.mtime(path)).to_i
          action = policy.action_for(age)
          next if action.nil?

          { "key" => row[:key], "path" => path, "action" => action.to_s, "age_seconds" => age }
        end
      end

      def entry_matches?(mentry, prefix:, zone:)
        return false if zone && mentry.zone != zone
        return false if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

        true
      end
    end
  end
end
