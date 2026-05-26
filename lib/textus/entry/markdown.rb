require "yaml"

module Textus
  module Entry
    # Markdown with YAML frontmatter. Original Entry implementation.
    class Markdown < Base
      def self.parse(raw, path: nil)
        raw = raw.dup.force_encoding(Encoding::UTF_8)
        raise BadFrontmatter.new(path, "entry is not valid UTF-8") unless raw.valid_encoding?
        return { "_meta" => {}, "body" => raw, "content" => nil } unless raw.start_with?("---\n") || raw.start_with?("---\r\n")

        lines = raw.split(/\r?\n/, -1)
        close_idx = lines[1..].index("---")
        raise BadFrontmatter.new(path, "frontmatter not terminated") unless close_idx

        close_idx += 1
        fm_yaml = lines[1...close_idx].join("\n")
        body = lines[(close_idx + 1)..].join("\n")
        begin
          fm = fm_yaml.strip.empty? ? {} : ::YAML.safe_load(fm_yaml, permitted_classes: [Date, Time], aliases: false)
        rescue Psych::SyntaxError => e
          raise BadFrontmatter.new(path, "YAML parse failed: #{e.message}")
        end
        fm = {} unless fm.is_a?(Hash)
        { "_meta" => fm, "body" => body, "content" => nil }
      end

      def self.serialize(meta:, body:, content: nil)
        _ = content # markdown ignores content
        fm_yaml = meta.empty? ? "" : ::YAML.dump(meta).sub(/\A---\n/, "")
        body = body.to_s
        body += "\n" unless body.empty? || body.end_with?("\n")
        "---\n#{fm_yaml}---\n#{body}"
      end

      def self.extensions = [".md"]

      def self.nested_glob = "**/*.md"

      def self.validate_path_extension(path, _nested)
        ext = File.extname(path)
        return if ["", ".md"].include?(ext)

        raise UsageError.new("markdown format requires '.md' path (got #{ext.inspect})")
      end
    end
  end
end
