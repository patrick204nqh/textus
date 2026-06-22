require "json"

module Textus
  module Format
    class Json < Base
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

      def self.validate_against(schema, parsed)
        schema.validate!(parsed["content"] || {})
      end

      def self.extensions = [".json"]

      def self.nested_glob = "**/*.json"

      def self.serialize_for_put(meta:, body:, content:, path:)
        raise UsageError.new("put for json requires content: or body:") if content.nil? && (body.nil? || body.to_s.empty?)

        if content.nil?
          begin
            parsed = parse(body.to_s, path: path)
          rescue BadFrontmatter => e
            raise BadContent.new(path, "bad_content: #{e.message}")
          end
          [body.to_s, parsed["_meta"], body.to_s, parsed["content"]]
        else
          bytes = serialize(meta: meta, body: "", content: content)
          [bytes, meta, bytes, content]
        end
      end

      def self.validate_path_extension(path, nested)
        ext = File.extname(path)
        if nested
          return if ext == ""

          raise UsageError.new("nested json path must not have an extension")
        end

        return if ext == ".json"

        raise UsageError.new("json format requires '.json' path (got #{ext.inspect})")
      end

      def self.data_to_payload(data)
        data = data.transform_keys(&:to_s) if data.is_a?(Hash)
        { meta: data["_meta"] || {}, body: nil, content: data["content"] || data }
      end
    end
  end
end
