module Textus
  module Domain
    class Staleness
      def initialize(manifest:)
        @manifest = manifest
        @generator_check = GeneratorCheck.new(manifest: manifest)
        @intake_check = IntakeCheck.new(manifest: manifest)
      end

      def call(prefix: nil, zone: nil)
        @manifest.entries
                 .select { |m| entry_matches?(m, prefix: prefix, zone: zone) }
                 .flat_map { |m| @generator_check.rows_for(m) + @intake_check.rows_for(m) }
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
