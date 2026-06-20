module Textus
  module Contract
    JSON_TYPES = {
      String => "string", Integer => "integer", Hash => "object",
      Array => "array", :boolean => "boolean"
    }.freeze

    def self.json_type(type)
      JSON_TYPES.fetch(type) { raise ArgumentError.new("no JSON type mapping for #{type.inspect}") }
    end
  end
end
