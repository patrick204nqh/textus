module Textus
  module Surface
    module Dispatch
      module_function

      def call(session, verb_name, raw_args = nil, **bound)
        if raw_args
          spec = Textus::Protocol::VerbRegistry.for(verb_name.to_sym)
          raise Textus::UsageError.new("unknown verb: #{verb_name}") unless spec

          bound = Textus::Protocol::Binder.inputs_from_wire(spec, raw_args)
        end
        session.public_send(verb_name.to_sym, **bound)
      end
    end
  end
end
