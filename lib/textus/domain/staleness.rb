module Textus
  module Domain
    class Staleness
      # ADR 0079: intake (age-based) staleness moved to the unified lifecycle
      # path (Domain::Lifecycle / freshness); only generator/build drift —
      # dependency-based, surfaced by the doctor `generator_drift` check —
      # remains here.
      def initialize(manifest:, file_stat:, clock: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = manifest
        @generator_check = GeneratorCheck.new(manifest: manifest, file_stat: file_stat)
      end

      def call(prefix: nil, zone: nil)
        @manifest.data.entries
                 .select { |m| entry_matches?(m, prefix: prefix, zone: zone) }
                 .flat_map { |m| @generator_check.rows_for(m) }
      end

      private

      def entry_matches?(mentry, prefix:, zone:)
        return false if zone && mentry.zone != zone
        return false if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

        true
      end
    end
  end
end
