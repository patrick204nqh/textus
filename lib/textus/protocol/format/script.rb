module Textus
  module Protocol
    module Format
      class Script < Base
        EXTENSIONS = %w[.rb .py .sh .js .pl .rs .exs].freeze

        def self.parse(raw, path: nil)
          raw = raw.dup.force_encoding(Encoding::UTF_8)
          raise BadFrontmatter.new(path, "entry is not valid UTF-8") unless raw.valid_encoding?

          { "_meta" => {}, "body" => raw, "content" => nil }
        end

        def self.serialize(meta:, body:, content: nil)
          _ = meta
          _ = content
          b = body.to_s
          b += "\n" unless b.empty? || b.end_with?("\n")
          b
        end

        def self.extensions = EXTENSIONS
        def self.nested_glob = "**/*"
        def self.nested_ext(*) = ""
        def self.enforce_name_match!(_path, _meta); end

        def self.rewrite_name(_path, _basename)
          false
        end

        def self.validate_path_extension(path, nested)
          ext = File.extname(path)
          if nested
            return if ext == ""

            raise UsageError.new("nested script path must not have an extension")
          end

          return if EXTENSIONS.include?(ext) || ext == ""

          raise UsageError.new("script format requires #{EXTENSIONS.join(" | ")} extension (got #{ext.inspect})")
        end

        def self.validate_raw_entry!(_parsed, lane)
          nil unless lane == "scratchpad"
        end


      end
    end
  end
end
