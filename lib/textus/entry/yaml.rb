require "yaml"

module Textus
  module Entry
    # YAML entry storage. Top-level must be a mapping so we can carry _meta.
    class Yaml < Base
      def self.parse(raw, path: nil)
        raw = raw.dup.force_encoding(Encoding::UTF_8)
        raise BadFrontmatter.new(path, "entry is not valid UTF-8") unless raw.valid_encoding?

        begin
          parsed = ::YAML.safe_load(raw, permitted_classes: [Date, Time], aliases: false)
        rescue Psych::SyntaxError, Psych::AliasesNotEnabled, Psych::DisallowedClass => e
          raise BadFrontmatter.new(path, "YAML parse failed: #{e.message}")
        end
        raise BadFrontmatter.new(path, "YAML top-level must be a mapping") unless parsed.is_a?(Hash)

        meta = parsed["_meta"]
        fm = meta.is_a?(Hash) ? meta : {}
        content_without_meta = parsed.except("_meta")
        { "_meta" => fm, "body" => raw, "content" => content_without_meta }
      end

      def self.serialize(meta:, body:, content: nil)
        if content.is_a?(Hash)
          # Re-inject _meta as the first key so on-disk shape is stable.
          on_disk = meta && !meta.empty? ? { "_meta" => meta }.merge(content) : content
          ::YAML.dump(on_disk).sub(/\A---\n/, "")
        elsif body && !body.to_s.empty?
          b = body.to_s
          b += "\n" unless b.end_with?("\n")
          b
        else
          raise UsageError.new("yaml serialize requires :content or :body")
        end
      end

      def self.validate_against(schema, parsed)
        schema.validate!(parsed["content"] || {})
      end

      def self.extensions = [".yaml", ".yml"]

      def self.nested_glob = "**/*.{yaml,yml}"

      def self.validate_path_extension(path, nested)
        ext = File.extname(path)
        if nested
          return if ext == ""

          raise UsageError.new("nested yaml path must not have an extension")
        end

        return if [".yaml", ".yml"].include?(ext)

        raise UsageError.new("yaml format requires '.yaml' or '.yml' path (got #{ext.inspect})")
      end
    end
  end
end
