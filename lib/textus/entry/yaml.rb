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

      def self.serialize_for_put(meta:, body:, content:, path:)
        raise UsageError.new("put for yaml requires content: or body:") if content.nil? && (body.nil? || body.to_s.empty?)

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

      # Mutating filesystem op; returns true if a write happened.
      def self.rewrite_name(path, basename) # rubocop:disable Naming/PredicateMethod
        raw = File.binread(path)
        parsed = parse(raw, path: path)
        meta = parsed["_meta"]
        return false unless meta.is_a?(Hash) && meta["name"].is_a?(String) && meta["name"] != basename

        new_meta = meta.merge("name" => basename)
        File.binwrite(path, serialize(meta: new_meta, body: "", content: parsed["content"]))
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
