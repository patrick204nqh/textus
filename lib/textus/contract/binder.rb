module Textus
  module Contract
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

    # The single argument binder for every surface (spike: collapses the three
    # historical implementations — MCP::Catalog.map_args, CLI::Runner.call_args,
    # and RoleScope's default-injection loop — into one algorithm).
    #
    # Input is a uniform `inputs` hash keyed by arg NAME (the use-case kwarg
    # name, never the wire name): each surface normalizes its own raw transport
    # shape (MCP JSON keyed by wire-name, CLI argv+flags, Ruby args+kwargs) into
    # this hash. Binder owns the shared algorithm and nothing transport-specific:
    #
    #   1. validate every required arg is present in `inputs`;
    #   2. for absentees, fall back to session_default (when a session is given)
    #      then to the literal default; otherwise omit the arg entirely;
    #   3. split into the (positional, keyword) pair to splat into the use-case,
    #      routing by `arg.positional`.
    #
    # Returns `[positional_array, keyword_hash]` — exactly what
    # `RoleScope#<verb>(*pos, **kw)` expects.
    module Binder
      module_function

      # `validate:` is a surface policy, not a contract invariant. The agent
      # surfaces (MCP, CLI) require declared args to be present so an agent gets
      # a crisp error instead of a downstream failure. The Ruby API trusts the
      # use-case's own keyword defaults (e.g. `put`'s `meta:` defaults to nil in
      # #call though it is `required: true` on the wire), so it binds leniently —
      # this is the spike's finding: `required:` means "required on the agent
      # wire," and the unified binder makes that distinction explicit rather than
      # accidental (it was previously masked by RoleScope skipping validation).
      def bind(spec, inputs, session: nil, validate: true)
        if validate
          missing = spec.required_args.reject { |a| inputs.key?(a.name) }
          raise MissingArgs.new(spec, missing) unless missing.empty?
        end

        pos = []
        kw  = {}
        spec.args.each do |a|
          if inputs.key?(a.name)
            value = inputs[a.name]
          elsif a.session_default && session
            value = session.public_send(a.session_default)
          elsif !a.default.nil?
            value = a.default
          else
            next
          end

          if a.positional
            pos << value
          else
            kw[a.name] = value
          end
        end
        [pos, kw]
      end

      # Normalize an ordered positional list + a by-name keyword hash (the shape
      # CLI argv+flags and Ruby args+kwargs both arrive in) into the uniform
      # by-name `inputs` hash bind expects. Positionals beyond what was supplied
      # are dropped so bind's required-check sees them as absent.
      def inputs_from_ordered(spec, ordered_positionals, by_name_keywords)
        names = spec.args.select(&:positional).map(&:name)
        names.zip(ordered_positionals).to_h.compact.merge(by_name_keywords)
      end
    end
  end
end
