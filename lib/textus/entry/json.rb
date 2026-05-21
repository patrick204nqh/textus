require "json"

module Textus
  module Entry
    # JSON entry storage. Top-level must be an object so we can carry _meta.
    module Json
      def self.parse(raw, path: nil)
        raw = raw.dup.force_encoding(Encoding::UTF_8)
        raise BadFrontmatter.new(path, "entry is not valid UTF-8") unless raw.valid_encoding?

        begin
          parsed = ::JSON.parse(raw)
        rescue ::JSON::ParserError => e
          raise BadFrontmatter.new(path, "JSON parse failed: #{e.message}")
        end
        raise BadFrontmatter.new(path, "JSON top-level must be an object") unless parsed.is_a?(Hash)

        meta = parsed["_meta"]
        fm = meta.is_a?(Hash) ? meta : {}
        content_without_meta = parsed.except("_meta")
        { "_meta" => fm, "body" => raw, "content" => content_without_meta }
      end

      def self.serialize(meta:, body:, content: nil)
        if content.is_a?(Hash)
          # Re-inject _meta as the first key so on-disk shape is stable.
          on_disk = meta && !meta.empty? ? { "_meta" => meta }.merge(content) : content
          out = ::JSON.pretty_generate(on_disk)
          out += "\n" unless out.end_with?("\n")
          out
        elsif body && !body.to_s.empty?
          b = body.to_s
          b += "\n" unless b.end_with?("\n")
          b
        else
          raise UsageError.new("json serialize requires :content or :body")
        end
      end

      def self.extensions = [".json"]
    end
  end
end
