module Textus
  module Entry
    # Plain-text entry storage. No frontmatter or structured content.
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

      def self.nested_glob = "**/*.txt"

      def self.inject_uid(meta, content, _existing_uid)
        [meta, content]
      end

      def self.enforce_name_match!(_path, _meta)
        # text has no meta home; no-op
      end

      def self.serialize_for_put(meta:, body:, content:, path:)
        _ = path
        _ = content
        bytes = serialize(meta: meta || {}, body: body.to_s)
        [bytes, meta, body.to_s, nil]
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
    end
  end
end
