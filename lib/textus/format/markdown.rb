require "yaml"

module Textus
  module Format
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
        _ = content
        fm_yaml = meta.empty? ? "" : ::YAML.dump(meta).sub(/\A---\n/, "")
        body = body.to_s
        body += "\n" unless body.empty? || body.end_with?("\n")
        "---\n#{fm_yaml}---\n#{body}"
      end

      def self.extensions = [".md"]

      def self.nested_glob = "**/*.md"

      def self.serialize_for_put(meta:, body:, content:, path:)
        _ = path
        _ = content
        bytes = serialize(meta: meta || {}, body: body.to_s)
        [bytes, meta, body.to_s, nil]
      end

      def self.rewrite_name(path, basename) # rubocop:disable Naming/PredicateMethod
        raw = File.binread(path)
        parsed = parse(raw, path: path)
        meta = parsed["_meta"] || {}
        return false unless meta.is_a?(Hash) && meta["name"].is_a?(String) && meta["name"] != basename

        new_meta = meta.merge("name" => basename)
        File.binwrite(path, serialize(meta: new_meta, body: parsed["body"]))
        true
      end

      def self.enforce_name_match!(path, meta)
        return unless meta.is_a?(Hash) && meta["name"]

        ext = extensions.first
        basename = File.basename(path, ext)
        return if meta["name"] == basename

        raise BadFrontmatter.new(path, "name '#{meta["name"]}' does not match basename '#{basename}'")
      end

      def self.inject_uid(meta, content, existing_uid)
        m = meta.is_a?(Hash) ? meta.dup : {}
        m["uid"] = existing_uid || Textus::Uid.mint unless m["uid"].is_a?(String) && !m["uid"].empty?
        [m, content]
      end

      def self.validate_path_extension(path, _nested)
        ext = File.extname(path)
        return if ["", ".md"].include?(ext)

        raise UsageError.new("markdown format requires '.md' path (got #{ext.inspect})")
      end
    end
  end
end
