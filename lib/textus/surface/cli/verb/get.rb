module Textus
  module Surface
    class CLI
      class Verb
        class Get < Runner::Base
          self.spec = Textus::Action::Get.contract
          option :as_flag, "--as=ROLE"

          def invoke(store)
            key = positional.shift or raise UsageError.new("get requires a key")
            spec = Textus::Action::Get.contract
            result = store.gate.dispatch(spec: spec, inputs: { key: key }, role: resolved_role(store), surface: :cli)
            raise Textus::UnknownKey.new(key, suggestions: store.manifest.resolver.suggestions_for(key)) if result.nil?

            emit(result)
          end
        end
      end
    end
  end
end
