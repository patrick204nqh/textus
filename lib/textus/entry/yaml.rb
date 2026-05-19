require "yaml"

module Textus
  module Entry
    # YAML entry storage. Top-level must be a mapping so we can carry _meta.
    module Yaml
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
        { "frontmatter" => fm, "body" => raw, "content" => parsed }
      end

      def self.serialize(frontmatter:, body:, content: nil)
        _ = frontmatter
        if content.is_a?(Hash)
          ::YAML.dump(content).sub(/\A---\n/, "")
        elsif body && !body.to_s.empty?
          b = body.to_s
          b += "\n" unless b.end_with?("\n")
          b
        else
          raise UsageError.new("yaml serialize requires :content or :body")
        end
      end

      def self.extensions = [".yaml", ".yml"]
    end
  end
end
