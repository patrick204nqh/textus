require "yaml"

module Textus
  module Protocol
    class Schema
      attr_reader :name, :required, :optional, :fields, :raw

      def self.load(path)
        raw = YAML.safe_load_file(path, permitted_classes: [Symbol, Date, Time], aliases: false)
        new(raw)
      end

      def initialize(raw)
        @raw = raw || {}
        @name = @raw["name"]
        @required = Array(@raw["required"])
        @optional = Array(@raw["optional"])
        @fields = @raw["fields"] || {}
      end

      def to_h
        @raw
      end

      def maintained_by(field)
        meta = @fields[field] or return nil
        meta["maintained_by"]
      end

      def unowned_fields
        @fields.each_with_object([]) do |(name, spec), acc|
          next unless spec.is_a?(Hash)

          acc << name if spec["maintained_by"].nil?
        end
      end

      def evolution
        raw = @raw["evolution"] || {}
        raw.each_with_object({}) do |(k, v), h|
          h[k] = v.is_a?(Date) || v.is_a?(Time) ? v.to_s : v
        end
      end

      def validate!(frontmatter)
        missing = @required - frontmatter.keys
        raise Textus::SchemaViolation.new("missing" => missing) unless missing.empty?

        known = (@required + @optional).uniq
        frontmatter.each do |k, v|
          next unless @fields.key?(k)

          check_type!(k, v, @fields[k])
        end

        warnings = frontmatter.keys - known
        warnings.map { |w| "unknown field: #{w}" }
      end

      TYPE_VALIDATORS = {
        "string" => :validate_string,
        "number" => :validate_number,
        "boolean" => :validate_boolean,
        "enum" => :validate_enum,
        "array" => :validate_array,
        "object" => :validate_object,
      }.freeze

      private

      def check_type!(field, value, spec)
        type = spec["type"]
        return unless type

        send(TYPE_VALIDATORS[type], field, value, spec)
      end

      def validate_string(field, value, spec)
        bad!(field, "expected string") unless value.is_a?(String)
        return unless (max = spec["max"]) && value.bytesize > max

        bad!(field, "exceeds max #{max}")
      end

      def validate_number(field, value, _spec)
        bad!(field, "expected number") unless value.is_a?(Numeric)
      end

      def validate_boolean(field, value, _spec)
        bad!(field, "expected boolean") unless [true, false].include?(value)
      end

      def validate_enum(field, value, spec)
        values = Array(spec["values"])
        bad!(field, "not in enum #{values.inspect}") unless values.include?(value)
      end

      def validate_array(field, value, spec)
        bad!(field, "expected array") unless value.is_a?(Array)
        return unless (items = spec["items"])

        value.each_with_index { |v, i| check_type!("#{field}[#{i}]", v, items) }
      end

      def validate_object(field, value, spec)
        bad!(field, "expected object") unless value.is_a?(Hash)
        return unless (sub = spec["fields"])

        sub.each { |fk, fspec| check_type!("#{field}.#{fk}", value[fk], fspec) if value.key?(fk) }
      end

      def bad!(field, reason)
        raise Textus::SchemaViolation.new("field" => field, "reason" => reason)
      end
    end
  end
end
