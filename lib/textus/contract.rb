module Textus
  # Declarative, co-located interface contract for a verb. One source of truth
  # for the agent-facing summary, the argument schema, which transports expose
  # the verb, and how the return value is shaped for the wire. CLI/Ruby/MCP and
  # boot project from this; the MCP catalog is fully derived from it (ADR 0039).
  module Contract
    # One argument of a verb. `positional: true` means it is passed to the
    # use-case as a positional (e.g. `get(key)`); otherwise as a keyword.
    # `session_default` names a zero-arg method on `Textus::Session` (Symbol)
    # that supplies the value when the wire arg is absent; `nil` means no default.
    # `wire_name` is the name the arg carries on the wire (MCP JSON property / CLI
    # envelope key) when it must differ from the use-case kwarg `name` — e.g. `put`
    # takes the `meta:` kwarg but exposes `_meta` on the wire to match what `get`
    # returns and what the CLI `--stdin` envelope already speaks (ADR 0057).
    Arg = Data.define(:name, :type, :required, :positional, :session_default, :description, :wire_name, :default) do
      # The name used on the wire (defaults to the kwarg name).
      def wire = wire_name || name
    end

    JSON_TYPES = {
      String => "string", Integer => "integer", Hash => "object",
      Array => "array", :boolean => "boolean"
    }.freeze

    def self.json_type(type)
      JSON_TYPES.fetch(type) { raise ArgumentError.new("no JSON type mapping for #{type.inspect}") }
    end

    Spec = Data.define(:verb, :summary, :args, :surfaces, :views, :cli, :around) do
      def mcp? = surfaces.include?(:mcp)
      def cli? = surfaces.include?(:cli)

      # The output shaper for a surface; falls back to the default view. Every
      # view is invoked uniformly as `view.call(result, inputs)` — a view that
      # declares one parameter ignores `inputs` (procs tolerate extra args).
      def view(surface = :default) = views[surface] || views.fetch(:default)

      # Operator-facing command path. Defaults to the verb token; grouped verbs
      # declare e.g. `cli "schema show"`.
      def cli_path = cli || verb.to_s
      def cli_words = cli_path.split
      def cli_group = cli_words.size > 1 ? cli_words.first : nil
      def cli_leaf  = cli_words.last

      def required_args = args.select(&:required)

      # JSON-Schema object for MCP tools/list inputSchema.
      # Outer keys (:type, :properties, :required) are symbols; inner property
      # keys are strings — matches the MCP/JSON wire shape expected by clients.
      def input_schema
        props = args.to_h do |a|
          h = { "type" => Contract.json_type(a.type) }
          h["description"] = a.description if a.description
          [a.wire.to_s, h]
        end
        { type: "object", properties: props, required: required_args.map { |a| a.wire.to_s } }
      end
    end

    # Mixed onto a use-case class via `extend`. Calls accumulate into ivars,
    # frozen into a Spec on first read of `.contract`.
    module DSL
      def verb(name = nil)
        if name
          raise "contract already built; declare verb before reading .contract" if defined?(@__contract) && @__contract

          @__verb = name
        else
          @__verb
        end
      end

      def summary(text = nil)
        if text
          raise "contract already built; declare summary before reading .contract" if defined?(@__contract) && @__contract

          @__summary = text
        else
          @__summary
        end
      end

      def surfaces(*list)
        if list.empty?
          @__surfaces ||= []
        else
          raise "contract already built; declare surfaces before reading .contract" if defined?(@__contract) && @__contract

          @__surfaces = list
        end
      end

      def cli(path = nil)
        if path
          raise "contract already built; declare cli before reading .contract" if defined?(@__contract) && @__contract

          @__cli = path.to_s
        else
          @__cli
        end
      end

      def arg(name, type, required: false, positional: false, session_default: nil, description: nil, wire_name: nil, default: nil) # rubocop:disable Metrics/ParameterLists
        raise "contract already built; declare args before reading .contract" if defined?(@__contract) && @__contract

        (@__args ||= []) << Arg.new(
          name: name, type: type, required: required,
          positional: positional, session_default: session_default,
          description: description, wire_name: wire_name, default: default
        )
      end

      # Declare an output shaper. `view { ... }` is the default (MCP + Ruby);
      # `view(:cli) { ... }` overrides for the CLI. Both receive (result, inputs).
      def view(surface = :default, &blk)
        return (@__views ||= {})[surface] unless blk

        raise "contract already built; declare view before reading .contract" if defined?(@__contract) && @__contract

        (@__views ||= {})[surface] = blk
      end

      def contract?
        !@__verb.nil?
      end

      # rubocop:disable Naming/MemoizedInstanceVariableName
      # @__contract uses double-underscore to match the other accumulator ivars
      # (@__verb, @__args, etc.) and avoid name collision with user-defined `@contract`.
      def contract
        @__contract ||= Spec.new(
          verb: @__verb,
          summary: @__summary,
          args: (@__args || []).freeze,
          surfaces: (@__surfaces || []).freeze,
          views: ((@__views ||= {})[:default] ||= ->(v, _i) { v }) && @__views,
          cli: @__cli,
          around: @__around,
        )
      end
      # rubocop:enable Naming/MemoizedInstanceVariableName
    end
  end
end
