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

      def self.validate_path_extension(_path, _nested)
        raise NotImplementedError.new("#{name}.validate_path_extension not implemented")
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

      def self.data_to_payload(data)
        data = data.transform_keys(&:to_s) if data.is_a?(Hash)
        { meta: data["_meta"] || {}, body: data.to_s, content: nil }
      end
    end
  end
end
