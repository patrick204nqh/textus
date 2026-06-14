module Textus
  module Surfaces
    class CLI
      class Verb
        class Get < Runner::Base
          self.spec = Textus::Action::Get.contract
          option :as_flag, "--as=ROLE"

          def invoke(store)
            key = positional.shift or raise UsageError.new("get requires a key")
            result = session_for(store).get(key)
            raise Textus::UnknownKey.new(key, suggestions: store.manifest.resolver.suggestions_for(key)) if result.nil?

            emit(result.to_h_for_wire)
          end
        end
      end
    end
  end
end
