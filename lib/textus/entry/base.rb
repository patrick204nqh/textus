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
    end
  end
end
