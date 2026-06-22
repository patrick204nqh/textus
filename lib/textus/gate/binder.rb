module Textus
  class Gate
    class MissingArgs < Textus::Error
      attr_reader :spec, :missing

      def initialize(spec, missing)
        @spec = spec
        @missing = missing
        super("missing_args", "#{spec.verb}: missing #{missing.map(&:wire).join(", ")}")
      end
    end

    module Binder
      module_function

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
