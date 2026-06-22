module Textus
  module Surface
    class Projector
      def initialize(view_key: :default, binder_method: :inputs_from_wire)
        @view_key = view_key
        @binder_method = binder_method
      end

      def dispatch(verb_name, inputs:, store:, role:, session: nil)
        spec = VerbRegistry.for(verb_name.to_sym)
        raise Textus::UsageError.new("unknown verb: #{verb_name}") unless spec

        bound = Textus::Gate::Binder.public_send(@binder_method, spec, inputs)
        store.gate.dispatch(spec:, inputs: bound, role:, session:, surface: @view_key)
      end
    end
  end
end
