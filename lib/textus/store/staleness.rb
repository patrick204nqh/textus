module Textus
  class Store
    class Staleness
      def initialize(manifest:)
        @manifest = manifest
        @generator_check = GeneratorCheck.new(manifest: manifest)
        @intake_check = IntakeCheck.new(manifest: manifest)
      end

      def call(prefix: nil, zone: nil)
        @manifest.entries.flat_map do |mentry|
          next [] unless EntryFilter.match?(mentry, prefix: prefix, zone: zone)

          @generator_check.rows_for(mentry) + @intake_check.rows_for(mentry)
        end
      end
    end
  end
end
