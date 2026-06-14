# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class Capabilities < Base
        extend Textus::Contract::DSL

        verb :capabilities
        summary "Machine-readable contract surface: every verb, its transports, and arg schema."
        surfaces :cli, :mcp
        arg :verb, String, required: false, description: "filter to a single verb by name"
        view { |result, _i| result }

        BURN = :sync

        def initialize(verb: nil)
          super()
          @verb = verb
        end

        def args
          { verb: @verb }.compact
        end

        def call(**)
          klasses = Textus::Dispatcher::VERBS.values.select do |klass|
            klass.respond_to?(:contract?) && klass.contract?
          end

          rows = klasses.map { |klass| project(klass.contract) }
          rows.select! { |row| row["verb"] == @verb } if @verb
          { "verbs" => rows.sort_by { |row| row["verb"] } }
        end

        private

        def project(spec)
          {
            "verb" => spec.verb.to_s,
            "summary" => spec.summary,
            "surfaces" => spec.surfaces.map(&:to_s) + ["ruby"],
            "cli" => spec.cli? ? spec.cli_path : nil,
            "args" => spec.args.map { |arg| project_arg(arg) },
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
end
