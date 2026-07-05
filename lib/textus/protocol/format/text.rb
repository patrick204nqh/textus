module Textus
  module Protocol
    module Format
      class Text < Base
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

        def self.extensions = [".txt"]
        def self.nested_glob = "**/*"
        def self.append_ext_on_nested? = false
        def self.enforce_name_match!(_path, _meta); end

        def self.rewrite_name(_path, _basename) # rubocop:disable Naming/PredicateMethod
          false
        end

        def self.validate_path_extension(path, nested)
          ext = File.extname(path)
          if nested
            return if ext == ""

            raise UsageError.new("nested text path must not have an extension")
          end

          return if [".txt", ""].include?(ext)

          raise UsageError.new("text format requires '.txt' or no extension (got #{ext.inspect})")
        end

        def self.data_to_payload(data)
          data = data.transform_keys(&:to_s) if data.is_a?(Hash)
          { meta: data["_meta"] || {}, body: (data["body"] || "").to_s, content: nil }
        end
      end
    end
  end
end
