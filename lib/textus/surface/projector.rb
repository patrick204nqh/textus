module Textus
  module Surface
    class Projector
      def initialize(view_key: :default, binder_method: :inputs_from_wire)
        @view_key = view_key
        @binder_method = binder_method
      end

      def verbs(action_verbs = Textus::Action::VERBS)
        action_verbs.select { |_verb, klass|
          klass.respond_to?(:contract?) && klass.contract?
        }
      end

      def names(action_verbs = Textus::Action::VERBS)
        verbs(action_verbs).keys.map(&:to_s)
      end

      def dispatch(verb_name, inputs:, store:, role:, session: nil)
        klass = Textus::Action::VERBS.fetch(verb_name.to_sym)
        spec = klass.contract
        bound = Textus::Gate::Binder.public_send(@binder_method, spec, inputs)
        store.gate.dispatch(spec:, inputs: bound, role:, session:).then { |r|
          spec.view(@view_key).call(r, bound)
        }
      end
    end
  end
end
