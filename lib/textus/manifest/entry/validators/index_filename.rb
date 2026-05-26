module Textus
  class Manifest
    class Entry
      module Validators
        module IndexFilename
          def self.call(entry)
            return if entry.index_filename.nil?

            check_shape!(entry)
            check_extension!(entry)
          end

          def self.check_shape!(entry)
            raise UsageError.new("entry '#{entry.key}': index_filename requires nested: true") unless entry.nested

            unless entry.index_filename.is_a?(String) && !entry.index_filename.empty?
              raise UsageError.new("entry '#{entry.key}': index_filename must be a non-empty string")
            end

            return unless entry.index_filename.include?("/") || File.basename(entry.index_filename) != entry.index_filename

            raise UsageError.new("entry '#{entry.key}': index_filename must be a bare basename (no slashes)")
          end

          def self.check_extension!(entry)
            ext = File.extname(entry.index_filename)
            inferred = Textus::Entry.infer_from_extension(ext)

            if inferred.nil?
              raise UsageError.new(
                "entry '#{entry.key}': index_filename #{entry.index_filename.inspect} has unknown extension #{ext.inspect}",
              )
            end
            return if inferred == entry.format

            raise UsageError.new(
              "entry '#{entry.key}': index_filename extension #{ext.inspect} implies format #{inferred.inspect}, " \
              "but entry format is #{entry.format.inspect}",
            )
          end
        end
      end
    end
  end
end
