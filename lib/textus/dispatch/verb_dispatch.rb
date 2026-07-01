module Textus
  module Dispatch
    module VerbDispatch
      module_function

      def call(store:, verb:, inputs:)
        domain = Textus::VerbRegistry::VERB_DOMAIN.fetch(verb) do
          raise Textus::UsageError.new("#{verb} has no domain assignment")
        end

        store.public_send(domain, verb, **inputs)
      end
    end
  end
end
