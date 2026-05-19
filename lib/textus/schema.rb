require "yaml"

module Textus
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

    def evolution
      raw = @raw["evolution"] || {}
      raw.each_with_object({}) do |(k, v), h|
        h[k] = v.is_a?(Date) || v.is_a?(Time) ? v.to_s : v
      end
    end

    # Returns nil on success; raises SchemaViolation on hard failure.
    # Unknown fields produce warnings, returned as a String[] alongside.
    def validate!(frontmatter)
      missing = @required - frontmatter.keys
      raise SchemaViolation.new("missing" => missing) unless missing.empty?

      known = (@required + @optional).uniq
      frontmatter.each do |k, v|
        next unless @fields.key?(k)

        check_type!(k, v, @fields[k])
      end

      warnings = frontmatter.keys - known
      warnings.map { |w| "unknown field: #{w}" }
    end

    private

    def check_type!(field, value, spec) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      type = spec["type"]
      case type
      when "string"
        bad!(field, "expected string") unless value.is_a?(String)
        if (max = spec["max"]) && value.bytesize > max
          bad!(field, "exceeds max #{max}")
        end
      when "number"
        bad!(field, "expected number") unless value.is_a?(Numeric)
      when "boolean"
        bad!(field, "expected boolean") unless [true, false].include?(value)
      when "enum"
        values = Array(spec["values"])
        bad!(field, "not in enum #{values.inspect}") unless values.include?(value)
      when "array"
        bad!(field, "expected array") unless value.is_a?(Array)
        if (items = spec["items"])
          value.each_with_index { |v, i| check_type!("#{field}[#{i}]", v, items) }
        end
      when "object"
        bad!(field, "expected object") unless value.is_a?(Hash)
        if (sub = spec["fields"])
          sub.each { |fk, fspec| check_type!("#{field}.#{fk}", value[fk], fspec) if value.key?(fk) }
        end
      when nil
        # untyped — no check
        # unknown type spec — vendor extension; ignore
      end
    end

    def bad!(field, reason)
      raise SchemaViolation.new("field" => field, "reason" => reason)
    end
  end
end
