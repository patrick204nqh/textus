module Textus
  module Read
    # A machine-readable projection of the contract surface: every verb, the
    # transports it reaches, and its full argument schema — sourced from the
    # same Contract DSL the CLI/MCP/boot already project from (ADR 0039/0063).
    #
    # Integrators assert their docs against this in CI so they can't drift
    # (#161 F4 — patrick-nexus docs claimed "MCP exposes 3 verbs" while ~20 are
    # surfaced). It also makes the per-surface `dry_run` default asymmetry
    # (#161 F6) self-documenting: each arg carries both `default` (agent wire)
    # and `cli_default` (CLI), so the divergence is visible, not folklore.
    #
    # Pure contract introspection — it reads no store data; `container` is
    # accepted only for the uniform use-case constructor.
    class Capabilities
      extend Textus::Contract::DSL

      verb     :capabilities
      summary  "Machine-readable contract surface: every verb, its transports, and arg schema."
      surfaces :cli, :ruby, :mcp
      arg :verb, String, required: false, description: "filter to a single verb by name"
      view { |result, _i| result }

      def initialize(container: nil, call: nil); end

      def call(verb: nil)
        klasses = Textus::Dispatcher::VERBS.values.select { |k| contract?(k) }
        rows = klasses.map { |k| project(k.contract) }
        rows.select! { |r| r["verb"] == verb } if verb
        { "verbs" => rows.sort_by { |r| r["verb"] } }
      end

      private

      def contract?(klass)
        klass.respond_to?(:contract?) && klass.contract?
      end

      def project(spec)
        {
          "verb" => spec.verb.to_s,
          "summary" => spec.summary,
          "surfaces" => spec.surfaces.map(&:to_s),
          "cli" => spec.cli? ? spec.cli_path : nil,
          "args" => spec.args.map { |a| project_arg(a) },
        }
      end

      def project_arg(arg)
        out = {
          "name" => arg.wire.to_s,
          "type" => json_type(arg.type),
          "required" => arg.required,
          "positional" => arg.positional,
        }
        out["description"] = arg.description if arg.description
        out["default"] = arg.default unless arg.default.nil?
        out["cli_default"] = arg.cli_default unless arg.cli_default == :__unset
        out["session_default"] = arg.session_default.to_s if arg.session_default
        out
      end

      def json_type(type)
        Textus::Contract.json_type(type)
      rescue ArgumentError
        "string"
      end
    end
  end
end
