module Textus
  module Dispatch
    # Raised when a required arg is absent from the bound input. Surface
    # adapters translate this to their native error (MCP ToolError, CLI
    # UsageError); a direct Ruby call lets it surface as-is.
    class MissingArgs < Textus::Error
      attr_reader :spec, :missing

      def initialize(spec, missing)
        @spec = spec
        @missing = missing
        super("missing_args", "#{spec.verb}: missing #{missing.map(&:wire).join(", ")}")
      end
    end

    # Validates and resolves a by-name inputs hash against a contract spec.
    # Returns a flat hash with defaults and session_defaults filled in.
    # Every caller receives the same shape — no positional/kwarg split.
    module Binder
      module_function

      # Validation is unconditional: a `required:` arg absent from `inputs` is a
      # contract violation on every surface (ADR 0069). `required:` is now an
      # honest contract invariant, not a surface policy — args the use-case
      # treats as optional (e.g. `meta`, whose real requiredness lives in schema
      # validation downstream) are declared `required: false`, so this check
      # never fires spuriously and never needs an opt-out.
      def bind(spec, inputs, session: nil)
        missing = spec.required_args.reject { |a| inputs.key?(a.name) }
        raise MissingArgs.new(spec, missing) unless missing.empty?

        spec.args.each_with_object({}) do |a, h|
          if inputs.key?(a.name)
            h[a.name] = inputs[a.name]
          elsif a.session_default && session
            h[a.name] = session.public_send(a.session_default)
          elsif !a.default.nil?
            h[a.name] = a.default
          end
        end
      end

      def inputs_from_ordered(spec, ordered_positionals, by_name_keywords)
        names = spec.args.select(&:positional).map(&:name)
        names.zip(ordered_positionals).to_h.compact.merge(by_name_keywords)
      end

      def inputs_from_wire(spec, raw)
        raw ||= {}
        spec.args.each_with_object({}) do |a, h|
          h[a.name] = raw[a.wire.to_s] if raw.key?(a.wire.to_s)
        end
      end
    end
  end
end
