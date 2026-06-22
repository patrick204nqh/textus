module Textus
  module Format
    class Base
      def self.parse(_raw, path: nil)
        _ = path
        raise NotImplementedError.new("#{name}.parse not implemented")
      end

      def self.serialize(meta: {}, body: "", content: nil)
        _ = meta
        _ = body
        _ = content
        raise NotImplementedError.new("#{name}.serialize not implemented")
      end

      def self.extensions
        raise NotImplementedError.new("#{name}.extensions not implemented")
      end

      def self.validate_against(schema, parsed)
        schema.validate!(parsed["_meta"] || {})
      end

      def self.nested_glob
        raise NotImplementedError.new("#{name}.nested_glob not implemented")
      end

      def self.validate_path_extension(path, nested)
        ext = File.extname(path)
        if nested
          return if ext == ""

          raise UsageError.new("#{format_name} nested path must not have an extension")
        end

        return if extensions.include?(ext)

        raise UsageError.new("#{format_name} format requires '#{extensions.join("' or '")}' path (got #{ext.inspect})")
      end

      def self.enforce_name_match!(path, meta)
        return unless meta.is_a?(Hash) && meta["name"]

        ext = extensions.first
        basename = File.basename(path, ext)
        return if meta["name"] == basename

        raise BadFrontmatter.new(path, "name '#{meta["name"]}' does not match basename '#{basename}'")
      end

      def self.rewrite_name(path, basename) # rubocop:disable Naming/PredicateMethod
        raw = File.binread(path)
        parsed = parse(raw, path: path)
        meta = parsed["_meta"] || {}
        return false unless meta.is_a?(Hash) && meta["name"].is_a?(String) && meta["name"] != basename

        new_meta = meta.merge("name" => basename)
        File.binwrite(path, serialize(meta: new_meta, body: parsed["body"] || "", content: parsed["content"]))
        true
      end

      def self.format_name
        name.split("::").last.downcase
      end

      def self.validate_raw_entry!(_parsed, _lane); end

      def self.serialize_for_put(meta:, body:, content:, path:)
        _ = meta
        _ = body
        _ = content
        _ = path
        raise NotImplementedError.new("#{name}.serialize_for_put not implemented")
      end
    end
  end
end
