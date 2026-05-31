module Textus
  # Declarative, co-located interface contract for a verb. One source of truth
  # for the agent-facing summary, the argument schema, which transports expose
  # the verb, and how the return value is shaped for the wire. CLI/Ruby/MCP and
  # boot project from this; the MCP catalog is fully derived from it (ADR 0039).
  module Contract
    # One argument of a verb. `positional: true` means it is passed to the
    # use-case as a positional (e.g. `get(key)`); otherwise as a keyword.
    Arg = Data.define(:name, :type, :required, :positional, :description)

    JSON_TYPES = {
      String => "string", Integer => "integer", Hash => "object",
      Array => "array", :boolean => "boolean"
    }.freeze

    def self.json_type(type)
      JSON_TYPES.fetch(type) { raise ArgumentError.new("no JSON type mapping for #{type.inspect}") }
    end

    Spec = Data.define(:verb, :summary, :args, :surfaces, :response) do
      def mcp? = surfaces.include?(:mcp)

      def required_args = args.select(&:required)

      # JSON-Schema object for MCP tools/list inputSchema.
      def input_schema
        props = args.to_h do |a|
          h = { "type" => Contract.json_type(a.type) }
          h["description"] = a.description if a.description
          [a.name.to_s, h]
        end
        { type: "object", properties: props, required: required_args.map { |a| a.name.to_s } }
      end
    end

    # Mixed onto a use-case class via `extend`. Calls accumulate into ivars,
    # frozen into a Spec on first read of `.contract`.
    module DSL
      def verb(name = nil)
        name ? (@__verb = name) : @__verb
      end

      def summary(text = nil)
        text ? (@__summary = text) : @__summary
      end

      def surfaces(*list)
        list.empty? ? (@__surfaces ||= []) : (@__surfaces = list)
      end

      def arg(name, type, required: false, positional: false, description: nil)
        (@__args ||= []) << Arg.new(
          name: name, type: type, required: required,
          positional: positional, description: description
        )
      end

      def response(&blk)
        @__response = blk if blk
        @__response || ->(v) { v }
      end

      def contract?
        !@__verb.nil?
      end

      def contract
        @contract ||= Spec.new(
          verb: @__verb,
          summary: @__summary,
          args: (@__args || []).freeze,
          surfaces: (@__surfaces || []).freeze,
          response: response,
        )
      end
    end
  end
end
