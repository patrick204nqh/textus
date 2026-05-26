module Textus
  module Entry
    # Abstract base for entry format strategies. Each concrete strategy
    # owns parsing, serialization, file-extension claims, and schema
    # validation for entries declared with its format.
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

      # Default: validate the meta hash. Overridden by formats that put the
      # validatable payload elsewhere (json/yaml put it under "content").
      def self.validate_against(schema, parsed)
        schema.validate!(parsed["_meta"] || {})
      end

      def self.nested_glob
        raise NotImplementedError.new("#{name}.nested_glob not implemented")
      end

      def self.validate_path_extension(_path, _nested)
        raise NotImplementedError.new("#{name}.validate_path_extension not implemented")
      end

      def self.inject_uid(_meta, _content, _existing_uid)
        raise NotImplementedError.new("#{name}.inject_uid not implemented")
      end

      def self.enforce_name_match!(_path, _meta)
        raise NotImplementedError.new("#{name}.enforce_name_match! not implemented")
      end

      def self.serialize_for_put(meta:, body:, content:, path:)
        _ = meta
        _ = body
        _ = content
        _ = path
        raise NotImplementedError.new("#{name}.serialize_for_put not implemented")
      end

      def self.rewrite_name(_path, _basename)
        raise NotImplementedError.new("#{name}.rewrite_name not implemented")
      end
    end
  end
end
