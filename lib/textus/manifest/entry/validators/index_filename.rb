module Textus
  class Manifest
    class Entry
      module Validators
        module IndexFilename
          def self.call(entry)
            # Use raw to detect misuse on non-nested entries (typed attr stubs nil on Base).
            index_filename = entry.nested? ? entry.index_filename : entry.raw["index_filename"]
            return if index_filename.nil?

            check_shape!(entry, index_filename)
            check_extension!(entry, index_filename)
          end

          def self.check_shape!(entry, index_filename)
            raise UsageError.new("entry '#{entry.key}': index_filename requires nested: true") unless entry.nested?

            unless index_filename.is_a?(String) && !index_filename.empty?
              raise UsageError.new("entry '#{entry.key}': index_filename must be a non-empty string")
            end

            return unless index_filename.include?("/") || File.basename(index_filename) != index_filename

            raise UsageError.new("entry '#{entry.key}': index_filename must be a bare basename (no slashes)")
          end

          def self.check_extension!(entry, index_filename)
            ext = File.extname(index_filename)
            inferred = Textus::Entry.infer_from_extension(ext)

            if inferred.nil?
              raise UsageError.new(
                "entry '#{entry.key}': index_filename #{index_filename.inspect} has unknown extension #{ext.inspect}",
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
