module Textus
  class CLI
    class Verb
      class Get < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("get requires a key")
          result = operations_for(store).reads.get.call(key)
          raise Textus::UnknownKey.new(key, suggestions: store.manifest.suggestions_for(key)) if result.nil?

          emit(result.to_h_for_wire)
        end
      end
    end
  end
end
